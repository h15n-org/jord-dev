// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The journal as stored with SwiftData: a journey, its rides (legs) and their stops. The
// journal is the source of truth; Träwelling and the calendar mirror it.

import Foundation
import SwiftData

@Model
final class Journey {
    var sourceID: String
    var checkedInAt: Date
    var departure: Date
    var arrival: Date
    @Relationship(deleteRule: .cascade, inverse: \Leg.journey) var legs: [Leg] = []

    init(_ draft: JourneyDraft, checkedInAt: Date = .now) {
        sourceID = draft.id
        self.checkedInAt = checkedInAt
        departure = draft.departure
        arrival = draft.arrival
        legs = draft.legs.enumerated().map { Leg($1, index: $0) }
    }

    var draft: JourneyDraft? {
        JourneyDraft(legs: legs.sorted { $0.index < $1.index }.compactMap(\.draft))
    }

    @discardableResult
    func setStops(_ stops: [StopDraft], on ride: LegDraft) -> Leg? {
        guard stops.count >= 2, let leg = legs.first(where: { $0.draft?.id == ride.id }) else { return nil }
        let old = leg.stops
        leg.stops = stops.enumerated().map { Stop($1, index: $0) }
        old.forEach { modelContext?.delete($0) }
        if let draft {
            departure = draft.departure
            arrival = draft.arrival
        }
        return leg
    }

    func rideOverlapping(_ other: JourneyDraft) -> (ride: LegDraft, stops: [StopDraft]?)? {
        guard sourceID != other.id, departure < other.arrival, arrival > other.departure,
              let rides = draft?.legs,
              let ride = rides.first(where: { $0.departure < other.arrival && $0.arrival > other.departure })
        else { return nil }
        let exit = ride.stops.indices.dropFirst().dropLast().first {
            ride.stops[$0].distance(to: other.origin) <= 1000
        }
        return (ride, exit.map { Array(ride.stops[...$0]) })
    }

    var lastTraewellingFailure: String? {
        legs.sorted { $0.index < $1.index }
            .filter { $0.traewellingStatusID == nil }
            .compactMap { $0.events.last }
            .first { $0.failed }?.text
    }
}

@Model
final class Leg {
    var index: Int
    var mode: String
    var lineName: String
    var headsign: String?
    var agencyName: String?
    var tripID: String
    var traewellingStatusID: Int?
    var traewellingLog: String?
    var journey: Journey?
    @Relationship(deleteRule: .cascade, inverse: \Stop.leg) var stops: [Stop] = []

    init(_ draft: LegDraft, index: Int) {
        self.index = index
        mode = draft.mode
        lineName = draft.lineName
        headsign = draft.headsign
        agencyName = draft.agencyName
        tripID = draft.tripID
        traewellingStatusID = draft.traewellingStatusID
        stops = draft.stops.enumerated().map { Stop($1, index: $0) }
    }

    var draft: LegDraft? {
        let ordered = stops.sorted { $0.index < $1.index }.map(\.draft)
        guard ordered.count >= 2, let first = ordered.first, let last = ordered.last else { return nil }
        return LegDraft(
            mode: mode, lineName: lineName, headsign: headsign, agencyName: agencyName, tripID: tripID,
            origin: first, intermediateStops: Array(ordered.dropFirst().dropLast()), destination: last,
            traewellingStatusID: traewellingStatusID, traewellingLog: events)
    }

    var events: [TraewellingEvent] {
        (traewellingLog ?? "").split(separator: "\n").compactMap(TraewellingEvent.init(line:))
    }

    func record(_ text: String, failed: Bool = false) {
        let all = events + [TraewellingEvent(text: text, failed: failed)]
        traewellingLog = all.suffix(10).map(\.line).joined(separator: "\n")
    }
}

@Model
final class Stop {
    var index: Int
    var name: String
    var stopID: String
    var latitude: Double
    var longitude: Double
    var scheduledArrival: Date?
    var scheduledDeparture: Date?
    var arrival: Date?
    var departure: Date?
    var track: String?
    var leg: Leg?

    init(_ draft: StopDraft, index: Int) {
        self.index = index
        name = draft.name
        stopID = draft.stopID
        latitude = draft.latitude
        longitude = draft.longitude
        scheduledArrival = draft.scheduledArrival
        scheduledDeparture = draft.scheduledDeparture
        arrival = draft.arrival
        departure = draft.departure
        track = draft.track
    }

    var draft: StopDraft {
        StopDraft(
            name: name, stopID: stopID, latitude: latitude, longitude: longitude,
            scheduledArrival: scheduledArrival, scheduledDeparture: scheduledDeparture,
            arrival: arrival, departure: departure, track: track)
    }
}
