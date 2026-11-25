// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Matching the train the phone is on to a ride in the journal, and the app-wide model
// that keeps asking the train's portal while the app is open.

import Foundation

struct LiveRide: Sendable {
    let snapshot: TrainSnapshot
    let leg: LegDraft
    let board: TrainSnapshot.Stop?
    let alight: TrainSnapshot.Stop

    init?(snapshot: TrainSnapshot, journey: JourneyDraft) {
        guard let number = snapshot.number, Self.isPlausible(journey, at: snapshot.time ?? .now) else { return nil }
        for leg in journey.legs where leg.category == .longDistance {
            let numbers = leg.lineName.split { !$0.isNumber }.map(String.init)
            guard numbers.contains(number), let alight = Self.stop(at: leg.destination, in: snapshot) else { continue }
            self.snapshot = snapshot
            self.leg = leg
            self.alight = alight
            board = Self.stop(at: leg.origin, in: snapshot)
            return
        }
        return nil
    }

    private static func stop(at place: StopDraft, in snapshot: TrainSnapshot) -> TrainSnapshot.Stop? {
        snapshot.stops
            .map { ($0, $0.draft.distance(to: place)) }
            .filter { $0.1 < 1500 }
            .min { $0.1 < $1.1 }?.0
    }

    var isBeforeDestination: Bool { !alight.passed || alight.id == snapshot.nextStopID }

    var distanceToDestination: Double? {
        isBeforeDestination ? snapshot.distance(toStop: alight.id) : nil
    }

    var progress: Double? {
        guard let start = board?.distanceFromStart, let end = alight.distanceFromStart, end > start else { return nil }
        guard isBeforeDestination else { return 1 }
        guard let travelled = snapshot.distanceTravelled else { return nil }
        return min(1, max(0, (travelled - start) / (end - start)))
    }

    // MARK: Getting off elsewhere

    var otherExit: TrainSnapshot.Stop? {
        guard let board, let stop = snapshot.currentStop ?? snapshot.nextStop,
              stop.id != alight.id, stop.id != board.id,
              let from = snapshot.stops.firstIndex(where: { $0.id == board.id }),
              let to = snapshot.stops.firstIndex(where: { $0.id == stop.id }), to > from
        else { return nil }
        return stop
    }

    func stops(endingAt stop: TrainSnapshot.Stop) -> [StopDraft]? {
        guard let board,
              let from = snapshot.stops.firstIndex(where: { $0.id == board.id }),
              let to = snapshot.stops.firstIndex(where: { $0.id == stop.id }), to > from
        else { return nil }
        func known(_ place: StopDraft) -> StopDraft? {
            leg.stops.dropFirst().first { $0.distance(to: place) < 1500 }
        }
        let between = snapshot.stops[(from + 1)..<to].map { known($0.draft) ?? $0.draft }
        var last = known(stop.draft) ?? stop.draft
        last.scheduledArrival = last.scheduledArrival ?? stop.draft.scheduledArrival
        last.arrival = stop.draft.arrival ?? last.arrival
        last.track = stop.draft.track ?? last.track
        return [leg.origin] + between + [last]
    }

    static func isPlausible(_ journey: JourneyDraft, at date: Date = .now) -> Bool {
        guard journey.legs.contains(where: { $0.category == .longDistance }) else { return false }
        if ICEPortalClient.isReplaying { return true }
        return date > journey.departure.addingTimeInterval(-30 * 60) && date < journey.arrival.addingTimeInterval(3 * 3600)
    }
}

@MainActor @Observable
final class LiveTrain {
    private(set) var snapshot: TrainSnapshot?
    private var lastSeen: Date?

    private static let patience: TimeInterval = 180

    private var interval: Duration {
        if ICEPortalClient.isReplaying { return .seconds(3) }
        return .seconds(lastSeen == nil ? 120 : 20)
    }

    func run() async {
        while !Task.isCancelled {
            if let answer = await ICEPortalClient.shared.snapshot() {
                lastSeen = .now
                snapshot = answer
            } else if let seen = lastSeen, Date.now.timeIntervalSince(seen) > Self.patience {
                lastSeen = nil
                snapshot = nil
            }
            try? await Task.sleep(for: interval)
        }
    }

    func ride(of journey: JourneyDraft) -> LiveRide? {
        snapshot.flatMap { LiveRide(snapshot: $0, journey: journey) }
    }
}
