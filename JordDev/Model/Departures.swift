// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// A station's departures, and a train's whole run from which the ride between two of its
// stops is cut.

import Foundation

struct Departure: Identifiable, Sendable {
    var tripID: String
    var mode: String
    var lineName: String
    var headsign: String?
    var stop: StopDraft
    var isCancelled: Bool

    var id: String { "\(tripID)|\(stop.stopID)" }
    var time: Date { stop.scheduledDeparture ?? stop.departure ?? .distantPast }
    var category: TransitCategory { TransitCategory(mode: mode) }
}

struct DepartureBoard: Sendable {
    var departures: [Departure]
    var earlier: String?
    var later: String?
}

struct TrainRun: Sendable {
    let ride: LegDraft

    func stops(after departure: Departure) -> [StopDraft] {
        guard let index = index(of: departure) else { return [] }
        return Array(ride.stops[(index + 1)...])
    }

    func journey(from departure: Departure, to stop: StopDraft) -> JourneyDraft? {
        let stops = ride.stops
        guard let start = index(of: departure),
              let end = stops.indices.last(where: { $0 > start && stops[$0].stopID == stop.stopID })
        else { return nil }
        var leg = ride
        leg.origin = stops[start]
        leg.intermediateStops = Array(stops[(start + 1)..<end])
        leg.destination = stops[end]
        return JourneyDraft(legs: [leg])
    }

    private func index(of departure: Departure) -> Int? {
        let stops = ride.stops
        return stops.firstIndex { $0.stopID == departure.stop.stopID && $0.scheduledDeparture == departure.stop.scheduledDeparture }
            ?? stops.firstIndex { $0.stopID == departure.stop.stopID }
            ?? stops.firstIndex { $0.scheduledDeparture == departure.stop.scheduledDeparture && $0.name == departure.stop.name }
    }
}
