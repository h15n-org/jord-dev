// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Client for the Träwelling API: the account, looking up a train, creating, changing and
// deleting check-ins.

import Foundation

struct TraewellingClient: Sendable {
    static let tokenAccount = "traewelling-token"
    static var userAgent: String {
        "Jord/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") (+https://github.com/h15n-org/jord-dev)"
    }

    let token: String
    var baseURL = URL(string: "https://traewelling.de/api/v1")!

    struct User: Sendable {
        let id: Int
        let username: String
    }

    struct CheckIn: Sendable {
        let statusID: Int
        let leg: LegDraft
    }

    func user() async throws -> User {
        let response: Wrapped<UserDTO> = try await get("auth/user", [:])
        return User(id: response.data.id, username: response.data.username)
    }

    // MARK: Checking in

    struct Trip: Sendable {
        let lineName: String
        let stops: [TripStop]
    }

    struct TripStop: Sendable {
        let stationID: Int
        let latitude: Double
        let longitude: Double
        let arrivalPlanned: String?
        let departurePlanned: String?
        let arrival: Date?
        let departure: Date?
    }

    enum CheckInResult: Sendable {
        case created(statusID: Int)
        case conflict(statusID: Int?)
    }

    func trip(id: String, lineName: String) async throws -> Trip {
        let response: Wrapped<TripDTO> = try await get("trains/trip", [
            "hafasTripId": id, "lineName": lineName,
        ])
        return Trip(
            lineName: response.data.lineName ?? lineName,
            stops: response.data.stopovers.compactMap { $0.value?.tripStop })
    }

    func checkIn(
        tripID: String, lineName: String, from start: TripStop, to destination: TripStop, visibility: Int
    ) async throws -> CheckInResult {
        var body: [String: Any] = [
            "tripId": tripID, "lineName": lineName,
            "start": start.stationID, "destination": destination.stationID,
            "visibility": visibility, "business": 0,
        ]
        body["departure"] = start.departurePlanned
        body["arrival"] = destination.arrivalPlanned
        let (data, status) = try await send("POST", "trains/checkin", [:], body: body)
        switch status {
        case 200, 201:
            return .created(statusID: try JSONDecoder().decode(Wrapped<CreatedDTO>.self, from: data).data.status.id)
        case 409:
            let conflicts = try? JSONDecoder().decode(Wrapped<ConflictsDTO>.self, from: data).data.conflicts
            return .conflict(statusID: conflicts?.first?.id)
        default:
            throw Self.error(for: status)
        }
    }

    func checkIn(ofStatus statusID: Int) async throws -> CheckIn? {
        let status: Wrapped<StatusDTO> = try await get("status/\(statusID)", [:])
        return status.data.checkIn
    }

    func trip(ofStatus statusID: Int) async throws -> Trip {
        let status: Wrapped<StatusDTO> = try await get("status/\(statusID)", [:])
        guard let trip = status.data.checkin.hafasId else { throw TraewellingError.notFound }
        return try await self.trip(id: trip, lineName: status.data.checkin.lineName ?? "")
    }

    func changeDestination(ofStatus statusID: Int, to stop: TripStop) async throws {
        guard let arrival = stop.arrivalPlanned else { throw TraewellingError.notFound }
        let (_, status) = try await send("PUT", "status/\(statusID)", [:], body: [
            "destinationId": stop.stationID, "destinationArrivalPlanned": arrival,
        ])
        guard status == 200 else { throw Self.error(for: status) }
    }

    func signOut() async throws {
        let (_, status) = try await send("POST", "auth/logout", [:], body: nil)
        guard status == 200 else { throw Self.error(for: status) }
    }

    func deleteStatus(_ id: Int) async throws {
        let (_, status) = try await send("DELETE", "status/\(id)", [:], body: nil)
        guard [200, 204, 404].contains(status) else { throw Self.error(for: status) }
    }

    // MARK: Transport

    private func get<T: Decodable & Sendable>(_ path: String, _ query: [String: String]) async throws -> T {
        let (data, status) = try await send("GET", path, query, body: nil)
        guard status == 200 else { throw Self.error(for: status) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(
        _ method: String, _ path: String, _ query: [String: String], body: [String: Any]?
    ) async throws -> (Data, Int) {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            components.percentEncodedQuery = components.percentEncodedQuery?.replacing("+", with: "%2B")
        }
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.httpMethod = method
        // After a browser sign-in the token changes every hour; the session has the current one.
        let bearer = try await TraewellingSession.shared.accessToken() ?? token
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func error(for status: Int) -> TraewellingError {
        switch status {
        case 401, 403: .unauthorized
        case 404: .notFound
        default: .http(status)
        }
    }
}

enum TraewellingError: Error {
    case unauthorized
    case declined
    case notFound
    case http(Int)
}

// MARK: - Wire format (only the fields Jord reads)

private struct Wrapped<T: Decodable & Sendable>: Decodable, Sendable {
    let data: T
}

private struct UserDTO: Decodable, Sendable {
    let id: Int
    let username: String
}

private struct Lossy<T: Decodable & Sendable>: Decodable, Sendable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

private struct StatusDTO: Decodable, Sendable {
    let id: Int
    let checkin: CheckinDTO

    var checkIn: TraewellingClient.CheckIn? {
        guard var origin = checkin.origin.draft(stationPrefix: "trwl"),
              var destination = checkin.destination.draft(stationPrefix: "trwl")
        else { return nil }
        if let manual = checkin.manualDeparture.flatMap(TraewellingDate.parse) { origin.departure = manual }
        if let manual = checkin.manualArrival.flatMap(TraewellingDate.parse) { destination.arrival = manual }
        guard origin.scheduledDeparture ?? origin.departure != nil,
              destination.scheduledArrival ?? destination.arrival != nil
        else { return nil }
        let leg = LegDraft(
            mode: Self.mode(for: checkin.category),
            lineName: checkin.lineName ?? "",
            headsign: nil, agencyName: nil,
            tripID: checkin.tripUuid ?? "trwl-\(id)",
            origin: origin, intermediateStops: [], destination: destination,
            traewellingStatusID: id)
        return TraewellingClient.CheckIn(statusID: id, leg: leg)
    }

    private static func mode(for category: String?) -> String {
        switch category {
        case "nationalExpress": "HIGHSPEED_RAIL"
        case "national": "LONG_DISTANCE"
        case "regionalExp", "regional": "REGIONAL_RAIL"
        case "suburban": "SUBURBAN"
        case "subway": "SUBWAY"
        case "tram": "TRAM"
        case "bus": "BUS"
        case "ferry": "FERRY"
        default: "OTHER"
        }
    }
}

private struct CheckinDTO: Decodable, Sendable {
    let tripUuid: String?
    let hafasId: String?
    let category: String?
    let lineName: String?
    let origin: StopoverDTO
    let destination: StopoverDTO
    let manualDeparture: String?
    let manualArrival: String?
}

private struct StopoverDTO: Decodable, Sendable {
    struct Station: Decodable, Sendable {
        let id: Int?
        let name: String?
        let latitude: Double?
        let longitude: Double?
    }

    let station: Station?
    let name: String?
    let arrivalPlanned: String?
    let arrivalReal: String?
    let departurePlanned: String?
    let departureReal: String?
    let arrivalPlatformPlanned: String?
    let arrivalPlatformReal: String?
    let departurePlatformPlanned: String?
    let departurePlatformReal: String?
    let platform: String?

    func draft(stationPrefix: String) -> StopDraft? {
        guard let name = station?.name ?? name,
              let latitude = station?.latitude, let longitude = station?.longitude
        else { return nil }
        return StopDraft(
            name: name, stopID: station?.id.map { "\(stationPrefix):\($0)" } ?? "",
            latitude: latitude, longitude: longitude,
            scheduledArrival: arrivalPlanned.flatMap(TraewellingDate.parse),
            scheduledDeparture: departurePlanned.flatMap(TraewellingDate.parse),
            arrival: arrivalReal.flatMap(TraewellingDate.parse),
            departure: departureReal.flatMap(TraewellingDate.parse),
            track: departurePlatformReal ?? departurePlatformPlanned
                ?? arrivalPlatformReal ?? arrivalPlatformPlanned ?? platform)
    }
}

extension StopoverDTO {
    var tripStop: TraewellingClient.TripStop? {
        guard let id = station?.id, let latitude = station?.latitude, let longitude = station?.longitude
        else { return nil }
        return TraewellingClient.TripStop(
            stationID: id, latitude: latitude, longitude: longitude,
            arrivalPlanned: arrivalPlanned, departurePlanned: departurePlanned,
            arrival: arrivalPlanned.flatMap(TraewellingDate.parse),
            departure: departurePlanned.flatMap(TraewellingDate.parse))
    }
}

private struct TripDTO: Decodable, Sendable {
    let lineName: String?
    let stopovers: [Lossy<StopoverDTO>]
}

private struct CreatedDTO: Decodable, Sendable {
    struct Status: Decodable, Sendable {
        let id: Int
    }

    let status: Status
}

private struct ConflictsDTO: Decodable, Sendable {
    struct Status: Decodable, Sendable {
        let id: Int
    }

    let conflicts: [Status]
}

private enum TraewellingDate {
    static func parse(_ text: String) -> Date? {
        (try? Date(text, strategy: .iso8601))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }
}
