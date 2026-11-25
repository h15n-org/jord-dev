// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// One-way sync of journal rides into an Apple calendar: one event per trip, updated when
// the trip changes and removed when it is deleted. Nothing in the calendar changes the
// journal.

import CoreLocation
import EventKit
import Foundation
import SwiftData

enum CalendarSettings {
    static let enabledKey = "calendarEnabled"
    static let calendarKey = "calendarIdentifier"
    static let reminderKey = "calendarReminderMinutes"
    static let sinceKey = "calendarSince"

    static let reminderChoices = [0, 5, 10, 15, 30, 60]
}

@MainActor
enum CalendarSync {
    static let store = EKEventStore()

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    static var isRefused: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted || status == .writeOnly
    }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    static var calendars: [(account: String, calendars: [EKCalendar])] {
        let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
        return Dictionary(grouping: writable) { $0.source.title }
            .map { ($0.key, $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    static var chosen: EKCalendar? {
        let identifier = UserDefaults.standard.string(forKey: CalendarSettings.calendarKey) ?? ""
        if let calendar = store.calendar(withIdentifier: identifier), calendar.allowsContentModifications {
            return calendar
        }
        return store.defaultCalendarForNewEvents
    }

    static func reconcile(_ journeys: [Journey], context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: CalendarSettings.enabledKey), hasAccess,
              let calendar = chosen
        else { return }
        let reminder = UserDefaults.standard.integer(forKey: CalendarSettings.reminderKey)
        let before = Ledger.read()
        var ledger = before
        var changed = false
        var pending: [(id: String, event: EKEvent, mark: String)] = []

        for journey in journeys {
            guard let draft = journey.draft else { continue }
            let entry = TripEvent(draft, reminderMinutes: reminder)
            if let known = ledger[journey.sourceID] {
                guard known.mark != entry.mark else { continue }
                if let event = store.event(withIdentifier: known.event) {
                    entry.fill(event)
                    changed = (try? store.save(event, span: .thisEvent, commit: false)) != nil || changed
                }
                ledger[journey.sourceID]?.mark = entry.mark
            } else {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                entry.fill(event)
                guard (try? store.save(event, span: .thisEvent, commit: false)) != nil else { continue }
                changed = true
                // The identifier is only final once the event is committed; see below.
                pending.append((journey.sourceID, event, entry.mark))
            }
        }

        let listed = Set(journeys.map(\.sourceID))
        let unseen = ledger.keys.filter { !listed.contains($0) }
        if !unseen.isEmpty {
            let stillThere = (try? context.fetch(
                FetchDescriptor<Journey>(predicate: #Predicate { unseen.contains($0.sourceID) }))) ?? []
            let kept = Set(stillThere.map(\.sourceID))
            for id in unseen where !kept.contains(id) {
                if let known = ledger[id], let event = store.event(withIdentifier: known.event) {
                    changed = (try? store.remove(event, span: .thisEvent, commit: false)) != nil || changed
                }
                ledger[id] = nil
            }
        }

        if changed { try? store.commit() }
        for (id, event, mark) in pending {
            if let identifier = event.eventIdentifier { ledger[id] = Ledger.Entry(event: identifier, mark: mark) }
        }
        if ledger != before { Ledger.write(ledger) }
    }

    static func unwritten(_ journeys: [Journey]) -> [Journey] {
        let ledger = Ledger.read()
        return journeys.filter { ledger[$0.sourceID] == nil }
    }


    private enum Ledger {
        struct Entry: Codable, Equatable {
            var event: String
            var mark: String
        }

        static let key = "calendarEvents"

        static func read() -> [String: Entry] {
            guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
            return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
        }

        static func write(_ ledger: [String: Entry]) {
            UserDefaults.standard.set(try? JSONEncoder().encode(ledger), forKey: key)
        }
    }
}

struct TripEvent {
    let title: String
    let start: Date
    let end: Date
    let place: StopDraft
    let notes: String
    let reminderMinutes: Int

    init(_ draft: JourneyDraft, reminderMinutes: Int) {
        title = "\(draft.origin.name) → \(draft.destination.name)"
        start = draft.departure
        end = max(draft.arrival, draft.departure.addingTimeInterval(60))
        place = draft.origin
        notes = Self.notes(for: draft)
        self.reminderMinutes = reminderMinutes
    }

    var mark: String {
        [title, String(start.timeIntervalSinceReferenceDate), String(end.timeIntervalSinceReferenceDate),
         String(place.latitude), String(place.longitude), notes, String(reminderMinutes)]
            .joined(separator: "\u{1F}")
    }

    @MainActor
    func fill(_ event: EKEvent) {
        event.title = title
        event.startDate = start
        event.endDate = end
        let location = EKStructuredLocation(title: place.name)
        location.geoLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
        event.structuredLocation = location
        event.notes = notes
        event.alarms = reminderMinutes > 0 ? [EKAlarm(relativeOffset: TimeInterval(-reminderMinutes * 60))] : nil
    }

    private static func notes(for draft: JourneyDraft) -> String {
        var blocks: [String] = []
        for leg in draft.legs {
            var lines = [leg.headsign.map { String(localized: "\(leg.lineName) Richtung \($0)") } ?? leg.lineName]
            lines.append(line(leg.departure, leg.origin))
            lines.append(line(leg.arrival, leg.destination))
            blocks.append(lines.joined(separator: "\n"))
        }
        blocks.append(String(localized: "Eingetragen von Jord"))
        return blocks.joined(separator: "\n\n")
    }

    private static func line(_ time: Date, _ stop: StopDraft) -> String {
        let clock = time.formatted(date: .omitted, time: .shortened)
        guard let track = stop.track else { return "\(clock) \(stop.name)" }
        return String(localized: "\(clock) \(stop.name), Gl. \(track)")
    }
}
