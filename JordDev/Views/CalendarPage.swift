// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Profile page for the calendar, and the watcher that keeps calendar events in step with
// the journal while the app runs.

import EventKit
import SwiftData
import SwiftUI

struct CalendarPage: View {
    @AppStorage(CalendarSettings.enabledKey) private var enabled = false
    @AppStorage(CalendarSettings.calendarKey) private var calendarID = ""
    @AppStorage(CalendarSettings.reminderKey) private var reminder = 0
    @AppStorage(CalendarSettings.sinceKey) private var since = 0.0
    @State private var accounts: [(account: String, calendars: [EKCalendar])] = []
    @State private var refused = CalendarSync.isRefused
    @State private var earlier: [Journey] = []
    @State private var isAskingAboutEarlier = false
    @Query private var journeys: [Journey]
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    private var isOn: Bool { enabled && !refused }

    var body: some View {
        ProfilePage(title: "Kalender") {
            VStack(alignment: .leading, spacing: 0) {
                Toggle("Reisen in den Kalender eintragen", isOn: Binding(get: { isOn }, set: { turn($0) }))
                    .tint(Theme.ink)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Hairline()
                footnote("Jord trägt jede Reise ein, in die du eincheckst: mit Zug, Zeiten und Gleisen. Ändert sich die Reise in Jord, ändert sich der Termin. Löschst du sie, verschwindet er.")
            }
            .card()

            if refused {
                VStack(alignment: .leading, spacing: 0) {
                    footnote("Jord darf nicht auf deinen Kalender zugreifen. Erlaube in den Einstellungen den vollen Zugriff, damit Jord seine Termine auch ändern kann.")
                    Hairline()
                    Button("Einstellungen öffnen", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .padding(12)
                }
                .card()
            }

            if isOn {
                calendarCard
                reminderCard
                if !earlier.isEmpty {
                    earlierCard
                }
                Text("Bereits eingetragene Termine bleiben in ihrem Kalender, auch wenn du hier wechselst oder das Eintragen ausschaltest. Jord liest deine anderen Termine nicht.")
                    .font(.footnote)
                    .foregroundStyle(Theme.quiet)
                    .padding(.horizontal, 4)
            }
        }
        .task { refresh() }
        .onChange(of: journeys.count) { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in refresh() }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Kalender")
            ForEach(accounts, id: \.account) { account in
                Hairline()
                Text(account.account)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.quiet)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                ForEach(account.calendars, id: \.calendarIdentifier) { calendar in
                    Button {
                        calendarID = calendar.calendarIdentifier
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 12, height: 12)
                            Text(calendar.title)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 12)
                            if calendar.calendarIdentifier == selectedID {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(calendar.calendarIdentifier == selectedID ? .isSelected : [])
                }
            }
        }
        .padding(.bottom, 6)
        .card()
    }

    private var earlierCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            footnote(earlier.count == 1
                ? "Jord trägt Reisen ab dem Tag ein, an dem du das Eintragen eingeschaltet hast. Eine frühere Reise aus deinem Reisetagebuch steht nicht im Kalender."
                : "Jord trägt Reisen ab dem Tag ein, an dem du das Eintragen eingeschaltet hast. \(earlier.count) frühere Reisen aus deinem Reisetagebuch stehen nicht im Kalender.")
            Hairline()
            Button("Frühere Reisen eintragen", systemImage: "calendar.badge.plus") {
                isAskingAboutEarlier = true
            }
            .buttonStyle(OutlineButtonStyle())
            // On the button, so the question opens from it.
            .confirmationDialog(
                earlier.count == 1
                    ? "Eine frühere Reise in den Kalender eintragen?"
                    : "\(earlier.count) frühere Reisen in den Kalender eintragen?",
                isPresented: $isAskingAboutEarlier, titleVisibility: .visible
            ) {
                Button("Eintragen") {
                    CalendarSync.reconcile(earlier, context: context)
                    refresh()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Jede Reise wird ein Termin an ihrem Tag. Löschen kannst du sie danach nur einzeln im Kalender oder indem du die Reise in Jord löschst.")
            }
            .padding(12)
        }
        .card()
    }

    private var reminderCard: some View {
        HStack {
            Text("Erinnerung")
            Spacer(minLength: 12)
            Picker("Erinnerung", selection: $reminder) {
                ForEach(CalendarSettings.reminderChoices, id: \.self) { minutes in
                    if minutes == 0 {
                        Text("Keine").tag(minutes)
                    } else {
                        Text("\(minutes) min vor Abfahrt").tag(minutes)
                    }
                }
            }
            .labelsHidden()
            .tint(Theme.ink)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .card()
    }

    private var selectedID: String? { CalendarSync.chosen?.calendarIdentifier }

    private func turn(_ on: Bool) {
        guard on else {
            enabled = false
            return
        }
        Task {
            if await CalendarSync.requestAccess() {
                since = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
                enabled = true
            }
            refresh()
        }
    }

    private func refresh() {
        refused = CalendarSync.isRefused
        accounts = CalendarSync.hasAccess ? CalendarSync.calendars : []
        let start = Date(timeIntervalSinceReferenceDate: since)
        earlier = CalendarSync.unwritten(journeys.filter { $0.arrival < start })
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Theme.quiet)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.quiet)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }
}

struct CalendarKeeper: ViewModifier {
    @AppStorage(CalendarSettings.enabledKey) private var enabled = false
    @AppStorage(CalendarSettings.sinceKey) private var since = 0.0

    func body(content: Content) -> some View {
        content.background {
            if enabled {
                let recent = Date.now.addingTimeInterval(-3 * 86400)
                let from = max(Date(timeIntervalSinceReferenceDate: since), recent)
                CalendarWatcher(from: from)
                    .id(since)
            }
        }
    }
}

private struct CalendarWatcher: View {
    @Query private var journeys: [Journey]
    @AppStorage(CalendarSettings.calendarKey) private var calendarID = ""
    @AppStorage(CalendarSettings.reminderKey) private var reminder = 0
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    init(from: Date) {
        _journeys = Query(filter: #Predicate<Journey> { $0.arrival >= from })
    }

    private struct Trigger: Equatable {
        let marks: [String]
        let calendarID: String
        let isActive: Bool
    }

    var body: some View {
        let marks = journeys.compactMap { journey in
            journey.draft.map { "\(journey.sourceID)|\(TripEvent($0, reminderMinutes: reminder).mark)" }
        }
        Color.clear
            .task(id: Trigger(marks: marks, calendarID: calendarID, isActive: scenePhase == .active)) {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                CalendarSync.reconcile(journeys, context: context)
            }
    }
}
