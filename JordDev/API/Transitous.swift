// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Client for the timetable (MOTIS API as served by Transitous): station search, stations
// nearby, departures and a train's stops. Transitous asks clients to identify themselves
// and to keep requests light; a location is rounded to about 100 m before it is sent.
// API Info: https://transitous.org/api/ - **NO** commercial use allowed.

import Foundation

struct TransitousClient: Sendable {
    static let shared = TransitousClient()

    var baseURL = URL(string: "https://api.transitous.org/api")!
    private let session: URLSession

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": "JordDev/\(version) (\(Setup.contact))"]
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    func stations(matching text: String) async throws -> [Station] {
        let matches: [GeocodeMatch] = try await get("v1/geocode", [
            "text": text, "type": "STOP", "language": "de",
        ])
        let rail = matches.filter { !Set($0.modes ?? []).isDisjoint(with: Self.railModes) }
        let stations = (rail.isEmpty ? matches : rail).map(\.station)
        // The geocoder sometimes ranks a station that only shares "Hauptbahnhof" above the one
        // that was asked for. Stations matching every word of the query go first.
        let words = Self.words(text)
        let (full, partial) = stations.reduce(into: ([Station](), [Station]())) { result, station in
            let name = Self.words("\(station.name) \(station.area ?? "")")
            if words.allSatisfy({ word in name.contains { $0.hasPrefix(word) } }) {
                result.0.append(station)
            } else {
                result.1.append(station)
            }
        }
        return full + partial
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { $0 == "hbf" ? "hauptbahnhof" : String($0) }
    }

    func stations(nearLatitude latitude: Double, longitude: Double) async throws -> [Station] {
        let place = [latitude, longitude].map { String(format: "%.3f", $0) }.joined(separator: ",")
        let matches: [GeocodeMatch] = try await get("v1/reverse-geocode", [
            "place": place, "type": "STOP", "numResults": "30",
        ])
        var seen = Set<String>()
        return matches
            .filter { !Set($0.modes ?? []).isDisjoint(with: Self.railModes) }
            .filter { seen.insert($0.name).inserted }
            .prefix(5)
            .map(\.station)
    }

    func departures(from station: Station, time: Date, modes: String, cursor: String? = nil) async throws -> DepartureBoard {
        var query = ["stopId": station.id, "n": "20", "mode": modes, "language": "de"]
        if let cursor {
            query["pageCursor"] = cursor
        } else {
            query["time"] = time.formatted(.iso8601)
        }
        let response: StopTimesResponse = try await get("v5/stoptimes", query)
        // A train that crosses a border is in two countries' timetables. Keep the one that
        // names a platform.
        var seen: [String: Int] = [:]
        var departures: [Departure] = []
        for departure in response.stopTimes.compactMap(\.departure) {
            let number = departure.lineName.split { !$0.isNumber }.last.map(String.init) ?? departure.lineName
            let key = "\(departure.time.timeIntervalSince1970)|\(number)"
            if let index = seen[key] {
                if departures[index].stop.track == nil, departure.stop.track != nil { departures[index] = departure }
            } else {
                seen[key] = departures.count
                departures.append(departure)
            }
        }
        return DepartureBoard(
            departures: departures, earlier: response.previousPageCursor, later: response.nextPageCursor)
    }

    func run(of departure: Departure) async throws -> TrainRun? {
        let itinerary: Itinerary = try await get("v5/trip", ["tripId": departure.tripID, "language": "de"])
        guard let leg = itinerary.legs.first, let ride = leg.draft else { return nil }
        return TrainRun(ride: ride)
    }

    private static let railModes: Set<String> = [
        "HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL", "SUBURBAN",
    ]

    private func get<T: Decodable & Sendable>(_ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" alone, but servers read it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacing("+", with: "%2B")
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TransitousError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

enum TransitousError: Error {
    case http(Int)
}

// MARK: - Wire format (only the fields Jord reads)

private struct GeocodeMatch: Decodable, Sendable {
    struct Area: Decodable, Sendable {
        let name: String
        let `default`: Bool?
    }

    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let areas: [Area]?
    let modes: [String]?

    var station: Station {
        let area = areas?.first { $0.default == true }?.name
        return Station(id: id, name: name, area: area == name ? nil : area, latitude: lat, longitude: lon)
    }
}

private struct StopTimesResponse: Decodable, Sendable {
    struct StopTime: Decodable, Sendable {
        let place: Place
        let mode: String
        let tripId: String?
        let headsign: String?
        let displayName: String?
        let routeShortName: String?
        let tripShortName: String?
        let cancelled: Bool?
        let tripCancelled: Bool?

        var departure: Departure? {
            let stop = place.draft
            guard let tripId, stop.scheduledDeparture ?? stop.departure != nil else { return nil }
            return Departure(
                tripID: tripId, mode: mode, lineName: displayName ?? tripShortName ?? routeShortName ?? mode,
                headsign: headsign, stop: stop, isCancelled: cancelled == true || tripCancelled == true)
        }
    }

    let stopTimes: [StopTime]
    let previousPageCursor: String?
    let nextPageCursor: String?
}

private struct Itinerary: Decodable, Sendable {
    let legs: [ItineraryLeg]
}

private struct ItineraryLeg: Decodable, Sendable {
    let mode: String
    let from: Place
    let to: Place
    let intermediateStops: [Place]?
    let tripId: String?
    let displayName: String?
    let routeShortName: String?
    let tripShortName: String?
    let headsign: String?
    let agencyName: String?

    var draft: LegDraft? {
        guard let tripId else { return nil }
        return LegDraft(
            mode: mode,
            lineName: displayName ?? routeShortName ?? tripShortName ?? mode,
            headsign: headsign, agencyName: agencyName, tripID: tripId,
            origin: from.draft, intermediateStops: (intermediateStops ?? []).map(\.draft), destination: to.draft)
    }
}

private struct Place: Decodable, Sendable {
    let name: String
    let stopId: String?
    let lat: Double
    let lon: Double
    let arrival: Date?
    let departure: Date?
    let scheduledArrival: Date?
    let scheduledDeparture: Date?
    let track: String?
    let scheduledTrack: String?

    var draft: StopDraft {
        StopDraft(
            name: name, stopID: stopId ?? "", latitude: lat, longitude: lon,
            scheduledArrival: scheduledArrival, scheduledDeparture: scheduledDeparture,
            arrival: arrival, departure: departure, track: track ?? scheduledTrack)
    }
}
