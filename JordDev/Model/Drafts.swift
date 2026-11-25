// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain value types the views work with: stations, stops, rides and journeys as they come
// from the timetable or are read back from the journal.

import Foundation

struct Station: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let area: String?
    let latitude: Double
    let longitude: Double
}

struct StopDraft: Sendable {
    var name: String
    var stopID: String
    var latitude: Double
    var longitude: Double
    var scheduledArrival: Date?
    var scheduledDeparture: Date?
    var arrival: Date?
    var departure: Date?
    var track: String?

    func distance(to other: StopDraft) -> Double {
        Geo.metres(latitude, longitude, other.latitude, other.longitude)
    }

    var delayMinutes: Int? {
        let pairs = [(departure, scheduledDeparture), (arrival, scheduledArrival)]
        for case let (real?, planned?) in pairs {
            let minutes = Int((real.timeIntervalSince(planned) / 60).rounded())
            return minutes == 0 ? nil : minutes
        }
        return nil
    }
}

enum TransitCategory: Sendable {
    case longDistance, regional, suburban, metro, bus, other

    init(mode: String) {
        self = switch mode {
        case "HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL": .longDistance
        case "REGIONAL_RAIL", "REGIONAL_FAST_RAIL": .regional
        case "SUBURBAN": .suburban
        case "SUBWAY", "TRAM": .metro
        case "BUS", "COACH": .bus
        default: .other
        }
    }
}

struct TraewellingEvent: Sendable, Identifiable, Equatable {
    var date: Date
    var text: String
    var failed: Bool

    var id: String { "\(date.timeIntervalSince1970)|\(text)" }

    var line: String {
        "\(date.formatted(.iso8601))\t\(failed ? "x" : "-")\t\(text.replacing("\n", with: " "))"
    }

    init(date: Date = .now, text: String, failed: Bool) {
        self.date = date
        self.text = text
        self.failed = failed
    }

    init?(line: Substring) {
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let date = try? Date(String(parts[0]), strategy: .iso8601) else { return nil }
        self.init(date: date, text: String(parts[2]), failed: parts[1] == "x")
    }
}

struct LegDraft: Identifiable, Sendable {
    var mode: String
    var lineName: String
    var headsign: String?
    var agencyName: String?
    var tripID: String
    var origin: StopDraft
    var intermediateStops: [StopDraft]
    var destination: StopDraft
    var traewellingStatusID: Int?
    var traewellingLog: [TraewellingEvent] = []

    var id: String { "\(tripID)|\(origin.stopID)|\(destination.stopID)" }
    var stops: [StopDraft] { [origin] + intermediateStops + [destination] }
    var departure: Date { origin.scheduledDeparture ?? origin.departure ?? .distantPast }
    var arrival: Date { destination.scheduledArrival ?? destination.arrival ?? .distantPast }

    var category: TransitCategory { TransitCategory(mode: mode) }

    var symbolName: String {
        switch mode {
        case "HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL":
            "train.side.front.car"
        case "SUBURBAN", "SUBWAY", "TRAM":
            "tram.fill"
        case "BUS", "COACH":
            "bus.fill"
        case "FERRY":
            "ferry.fill"
        default:
            "arrow.triangle.swap"
        }
    }
}

struct JourneyDraft: Identifiable, Sendable {
    var legs: [LegDraft]

    init?(legs: [LegDraft]) {
        guard !legs.isEmpty else { return nil }
        self.legs = legs
    }

    var id: String { legs.map(\.id).joined(separator: "→") }
    var origin: StopDraft { legs[0].origin }
    var destination: StopDraft { legs[legs.count - 1].destination }
    var departure: Date { legs[0].departure }
    var arrival: Date { legs[legs.count - 1].arrival }
}

enum Geo {
    static func metres(_ latitude1: Double, _ longitude1: Double, _ latitude2: Double, _ longitude2: Double) -> Double {
        let metresPerDegree = 111_320.0
        let north = (latitude2 - latitude1) * metresPerDegree
        let east = (longitude2 - longitude1) * metresPerDegree * cos(latitude1 * .pi / 180)
        return (north * north + east * east).squareRoot()
    }
}
