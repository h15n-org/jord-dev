// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Sending the journal's rides to Träwelling: the user's settings, posting a check-in,
// moving its end, deleting it, and recording what Träwelling answered on each ride.

import Foundation
import SwiftData

enum TraewellingSettings {
    static let tokenPage = URL(string: "https://traewelling.de/settings/applications")!

    static let modeKey = "traewellingMode"

    enum Mode: String, CaseIterable, Identifiable {
        case ask, automatic, never

        var id: String { rawValue }
        var title: String {
            switch self {
            case .ask: String(localized: "Jedes Mal nachfragen")
            case .automatic: String(localized: "Automatisch einchecken")
            case .never: String(localized: "Nicht einchecken")
            }
        }
    }

    static var mode: Mode {
        UserDefaults.standard.string(forKey: modeKey).flatMap(Mode.init) ?? .ask
    }
    static let visibilityKey = "traewellingVisibility"
    static let defaultVisibility = 3

    static let visibilities: [(value: Int, title: String)] = [
        (0, String(localized: "Öffentlich")),
        (1, String(localized: "Ungelistet")),
        (2, String(localized: "Nur Follower")),
        (4, String(localized: "Nur angemeldete Nutzer")),
        (3, String(localized: "Privat")),
    ]

    static var client: TraewellingClient? {
        guard let token = Keychain.read(TraewellingClient.tokenAccount), !token.isEmpty else { return nil }
        return TraewellingClient(token: token)
    }

    static var visibility: Int {
        UserDefaults.standard.object(forKey: visibilityKey) as? Int ?? defaultVisibility
    }
}

@MainActor
enum TraewellingPush {
    enum Outcome: Equatable {
        case sending
        case sent
        case failed(String)
    }

    static func delete(_ journey: Journey, client: TraewellingClient) async -> String? {
        for leg in journey.legs {
            guard let statusID = leg.traewellingStatusID else { continue }
            do {
                try await client.deleteStatus(statusID)
                leg.traewellingStatusID = nil
                leg.record(String(localized: "Check-in \(String(statusID)) bei Träwelling gelöscht."))
            } catch {
                let reason = describe(error, line: leg.lineName)
                leg.record(String(localized: "Check-in \(String(statusID)) nicht gelöscht: \(reason)"), failed: true)
                return reason
            }
        }
        return nil
    }

    static func end(_ ride: LiveRide, at stop: TrainSnapshot.Stop, in journey: Journey) async -> Outcome? {
        guard let stops = ride.stops(endingAt: stop) else { return nil }
        return await end(ride.leg, stops: stops, in: journey)
    }

    static func end(_ ride: LegDraft, stops: [StopDraft], in journey: Journey) async -> Outcome? {
        guard let leg = journey.setStops(stops, on: ride),
              let statusID = leg.traewellingStatusID, let origin = stops.first, let destination = stops.last
        else { return nil }
        guard let client = TraewellingSettings.client else {
            return .failed(String(localized: "Bei Träwelling steht noch das alte Ziel. Verbinde dein Konto im Profil, um es zu ändern."))
        }
        do {
            let trip = try await client.trip(ofStatus: statusID)
            guard let ends = ends(of: trip, from: origin, to: destination) else { throw TraewellingError.notFound }
            try await client.changeDestination(ofStatus: statusID, to: ends.end)
            leg.record(String(localized: "Ziel von Check-in \(String(statusID)) auf \(destination.name) geändert."))
            return .sent
        } catch {
            let reason = String(localized: "Bei Träwelling steht noch das alte Ziel: \(describe(error, line: leg.lineName))")
            leg.record(reason + String(localized: " (Check-in \(String(statusID)))"), failed: true)
            return .failed(reason)
        }
    }

    static func hold(_ journey: Journey, behind other: LegDraft) {
        for leg in journey.legs where leg.traewellingStatusID == nil {
            leg.record(String(localized: "Noch nicht an Träwelling gesendet: Dort läuft noch der Check-in für \(other.lineName) nach \(other.destination.name)."), failed: true)
        }
    }

    static func sendHeld(_ journeys: [Journey], client: TraewellingClient) async {
        let recent = Date.now.addingTimeInterval(-2 * 86400)
        for journey in journeys
        where journey.checkedInAt > recent && isPending(journey) && journey.lastTraewellingFailure != nil {
            _ = await run(journey, client: client, visibility: TraewellingSettings.visibility)
        }
    }

    private static func isSameRide(_ ride: LegDraft, _ other: LegDraft) -> Bool {
        ride.origin.distance(to: other.origin) <= 1500
            && abs(ride.departure.timeIntervalSince(other.departure)) <= 30 * 60
    }

    static func isPending(_ journey: Journey) -> Bool {
        journey.legs.contains { $0.traewellingStatusID == nil }
    }

    static func status(of journey: Journey) -> Outcome? {
        isPending(journey) ? journey.lastTraewellingFailure.map(Outcome.failed) : .sent
    }

    static func run(_ journey: Journey, client: TraewellingClient, visibility: Int) async -> Outcome {
        for leg in journey.legs.sorted(by: { $0.index < $1.index }) where leg.traewellingStatusID == nil {
            guard let draft = leg.draft else { continue }
            do {
                switch try await post(draft, client: client, visibility: visibility) {
                case .created(let statusID):
                    leg.traewellingStatusID = statusID
                    leg.record(String(localized: "Eingecheckt: Träwelling hat Check-in \(String(statusID)) angelegt."))
                case .conflict(let statusID):
                    // Träwelling refuses a check-in that overlaps another. Only if that other
                    // one is this very ride does the ride count as being there.
                    let named = statusID.map { String(localized: " (Check-in \(String($0)))") } ?? ""
                    guard let statusID, let other = try? await client.checkIn(ofStatus: statusID) else {
                        let reason = String(localized: "Träwelling hat für \(draft.lineName) schon einen Check-in zur selben Zeit.")
                        leg.record(reason + named, failed: true)
                        return .failed(reason)
                    }
                    guard isSameRide(draft, other.leg) else {
                        let reason = String(localized: "Nicht bei Träwelling eingecheckt: Dort überschneidet sich die Fahrt mit einem anderen Check-in (\(other.leg.lineName), \(other.leg.origin.name) – \(other.leg.destination.name)).")
                        leg.record(reason + named, failed: true)
                        return .failed(reason)
                    }
                    leg.traewellingStatusID = statusID
                    leg.record(String(localized: "Träwelling hatte diese Fahrt schon: Check-in \(String(statusID)) übernommen."))
                }
            } catch {
                let reason = describe(error, line: draft.lineName)
                leg.record(String(localized: "Nicht eingecheckt: \(reason)"), failed: true)
                return .failed(reason)
            }
        }
        return .sent
    }

    private static func post(
        _ leg: LegDraft, client: TraewellingClient, visibility: Int
    ) async throws -> TraewellingClient.CheckInResult {
        let trip = try await client.trip(id: leg.tripID, lineName: leg.lineName)
        guard let ends = ends(of: trip, from: leg.origin, to: leg.destination) else { throw TraewellingError.notFound }
        return try await client.checkIn(
            tripID: leg.tripID, lineName: trip.lineName,
            from: ends.start, to: ends.end, visibility: visibility)
    }

    private static func ends(
        of trip: TraewellingClient.Trip, from origin: StopDraft, to destination: StopDraft
    ) -> (start: TraewellingClient.TripStop, end: TraewellingClient.TripStop)? {
        func metres(_ index: Int, _ target: StopDraft) -> Double {
            Geo.metres(trip.stops[index].latitude, trip.stops[index].longitude, target.latitude, target.longitude)
        }
        func find(
            _ target: StopDraft, planned: Date?, time: KeyPath<TraewellingClient.TripStop, Date?>, in indices: Range<Int>
        ) -> Int? {
            if let planned, let index = indices.first(where: {
                trip.stops[$0][keyPath: time].map { abs($0.timeIntervalSince(planned)) < 30 } == true
                    && metres($0, target) <= 5000
            }) {
                return index
            }
            return indices.map { ($0, metres($0, target)) }.filter { $0.1 <= 500 }.min { $0.1 < $1.1 }?.0
        }
        guard let start = find(origin, planned: origin.scheduledDeparture, time: \.departure, in: trip.stops.indices),
              let end = find(
                  destination, planned: destination.scheduledArrival, time: \.arrival,
                  in: (start + 1)..<trip.stops.count)
        else { return nil }
        return (trip.stops[start], trip.stops[end])
    }

    private static func describe(_ error: Error, line: String) -> String {
        switch error {
        case TraewellingError.unauthorized:
            String(localized: "Träwelling hat die Anmeldung abgelehnt. Verbinde dein Konto im Profil neu.")
        case TraewellingError.notFound:
            String(localized: "Träwelling kennt \(line) oder einen der beiden Bahnhöfe nicht.")
        case TraewellingError.http(let status):
            String(localized: "Träwelling hat mit Fehler \(status) geantwortet.")
        case is DecodingError:
            String(localized: "Die Antwort von Träwelling hatte ein unerwartetes Format.")
        default:
            String(localized: "Träwelling ist nicht erreichbar.")
        }
    }
}

@MainActor @Observable
final class TraewellingActivity {
    private var inFlight: [String: TraewellingPush.Outcome] = [:]

    func outcome(for journey: Journey) -> TraewellingPush.Outcome? {
        inFlight[journey.sourceID] ?? TraewellingPush.status(of: journey)
    }

    func canSend(_ journey: Journey) -> Bool {
        TraewellingSettings.client != nil && TraewellingPush.isPending(journey)
    }

    func send(_ journey: Journey, visibility: Int = TraewellingSettings.visibility) {
        guard let client = TraewellingSettings.client else { return }
        Task {
            await track(journey, showsSending: true) {
                await TraewellingPush.run(journey, client: client, visibility: visibility)
            }
        }
    }

    func end(_ ride: LiveRide, at stop: TrainSnapshot.Stop, in journey: Journey, among journeys: [Journey]) {
        Task {
            await track(journey, showsSending: ride.leg.traewellingStatusID != nil) {
                await TraewellingPush.end(ride, at: stop, in: journey)
            }
            if let client = TraewellingSettings.client { await TraewellingPush.sendHeld(journeys, client: client) }
        }
    }

    func end(_ ride: LegDraft, stops: [StopDraft], in journey: Journey) async {
        await track(journey, showsSending: ride.traewellingStatusID != nil) {
            await TraewellingPush.end(ride, stops: stops, in: journey)
        }
    }

    private func track(
        _ journey: Journey, showsSending: Bool, _ work: () async -> TraewellingPush.Outcome?
    ) async {
        let key = journey.sourceID
        if showsSending { inFlight[key] = .sending }
        let outcome = await work()
        if case .failed = outcome { inFlight[key] = outcome } else { inFlight[key] = nil }
    }
}
