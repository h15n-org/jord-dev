// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Reads the on-board portal of an ICE (WIFIonICE): speed, position and stops of the train
// the phone is on. In debug builds, recorded answers can be replayed.

import Foundation

struct TrainSnapshot: Sendable {
    var lineName: String?
    var number: String?
    var series: String?
    var trainset: String?
    var speed: Double?
    var time: Date?

    var stops: [Stop] = []
    var nextStopID: String?
    var lastStopID: String?
    var finalStationName: String?
    var distanceFromLastStop: Double?

    struct Stop: Sendable, Identifiable {
        var draft: StopDraft
        var passed: Bool
        var distanceFromStart: Double?
        var arrivalDelay: String?
        var departureDelay: String?

        var id: String { draft.stopID }
    }

    var nextStop: Stop? { stops.first { $0.id == nextStopID } }
    var lastStop: Stop? { stops.first { $0.id == lastStopID } }

    var distanceTravelled: Double? {
        if lastStopID == nil, nextStopID == stops.first?.id, !stops.isEmpty { return 0 }
        guard let last = lastStop?.distanceFromStart else { return nil }
        return last + (distanceFromLastStop ?? 0)
    }

    var distanceToNextStop: Double? {
        guard let next = nextStop?.distanceFromStart, let travelled = distanceTravelled else { return nil }
        return max(0, next - travelled)
    }

    var isAtStation: Bool {
        guard (speed ?? 0) < 1 else { return false }
        return lastStopID == nil || (distanceToNextStop ?? .infinity) < 300
            || (distanceFromLastStop ?? .infinity) < 300
    }

    var currentStop: TrainSnapshot.Stop? {
        guard isAtStation else { return nil }
        if lastStopID == nil || (distanceToNextStop ?? .infinity) < 300 { return nextStop }
        return lastStop
    }

    func distance(toStop id: String) -> Double? {
        guard let stop = stops.first(where: { $0.id == id }), !stop.passed || id == nextStopID,
              let target = stop.distanceFromStart, let travelled = distanceTravelled
        else { return nil }
        return max(0, target - travelled)
    }
}

struct ICEPortalClient: Sendable {
    static let shared = ICEPortalClient()

    var baseURL = URL(string: "https://iceportal.de/api1/rs")!
    private let session: URLSession

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": "Jord/\(version) (+https://github.com/h15n-org/jord-dev)", "Accept": "application/json"]
        configuration.timeoutIntervalForRequest = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func snapshot() async -> TrainSnapshot? {
        #if DEBUG
        if let replay = Self.replay {
            let (status, trip) = await replay.next()
            return Self.snapshot(status: status, trip: trip)
        }
        #endif
        async let status = body("status")
        async let trip = body("tripInfo/trip")
        return Self.snapshot(status: await status, trip: await trip)
    }

    static func snapshot(status: Data?, trip: Data?) -> TrainSnapshot? {
        let decoder = JSONDecoder()
        let status = status.flatMap { try? decoder.decode(StatusDTO.self, from: $0) }
        let trip = trip.flatMap { try? decoder.decode(TripInfoDTO.self, from: $0) }?.trip
        guard status != nil || trip != nil else { return nil }

        var snapshot = TrainSnapshot()
        let trainType = filled(status?.trainType) ?? filled(trip?.trainType)
        snapshot.number = filled(status?.vzn?.text) ?? filled(trip?.vzn?.text)
        snapshot.lineName = filled(trip?.journeyDisplayValue)
            ?? [trainType, snapshot.number].compactMap { $0 }.joined(separator: " ").nilIfEmpty
        snapshot.series = filled(status?.series)
        snapshot.trainset = filled(status?.tzn)
        snapshot.speed = status?.speed
        snapshot.time = date(status?.serverTime)

        snapshot.stops = (trip?.stops ?? []).compactMap(\.stop)
        snapshot.nextStopID = filled(trip?.stopInfo?.actualNext) ?? filled(trip?.stopInfo?.scheduledNext)
        snapshot.lastStopID = filled(trip?.stopInfo?.actualLast)
        snapshot.finalStationName = filled(trip?.stopInfo?.finalStationName)
        snapshot.distanceFromLastStop = trip?.distanceFromLastStop
        return snapshot
    }

    // MARK: Replay

    #if DEBUG
    static let isReplaying = replay != nil

    private static let replay: Replay? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-icePortalSamples"), arguments.count > index + 1 else { return nil }
        return Replay(folder: URL(fileURLWithPath: arguments[index + 1]))
    }()

    private actor Replay {
        private let folder: URL
        private let stamps: [String]
        private var position = 0

        init(folder: URL) {
            self.folder = folder
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            stamps = Set(names.filter { $0.hasSuffix(".json") }.map { String($0.prefix(15)) }).sorted()
        }

        func next() -> (status: Data?, trip: Data?) {
            guard !stamps.isEmpty else { return (nil, nil) }
            let stamp = stamps[position % stamps.count]
            position += 1
            return (
                try? Data(contentsOf: folder.appending(path: "\(stamp)-status.json")),
                try? Data(contentsOf: folder.appending(path: "\(stamp)-tripInfo-trip.json")))
        }
    }
    #else
    static let isReplaying = false
    #endif

    // MARK: Transport

    private func body(_ path: String) async -> Data? {
        guard let (data, response) = try? await session.data(from: baseURL.appending(path: path)),
              (response as? HTTPURLResponse)?.statusCode == 200, data.first == UInt8(ascii: "{")
        else { return nil }
        return data
    }

    private static func filled(_ text: String?) -> String? { text?.nilIfEmpty }

    fileprivate static func date(_ milliseconds: Double?) -> Date? {
        milliseconds.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    // MARK: Wire format

    private struct Loose: Decodable {
        let text: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                text = String(number)
            } else {
                text = try container.decode(String.self)
            }
        }
    }

    private struct StatusDTO: Decodable {
        let series: String?
        let serverTime: Double?
        let speed: Double?
        let trainType: String?
        let tzn: String?
        let vzn: Loose?
    }

    private struct TripInfoDTO: Decodable {
        let trip: TripDTO?
    }

    private struct TripDTO: Decodable {
        let trainType: String?
        let vzn: Loose?
        let journeyDisplayValue: String?
        let distanceFromLastStop: Double?
        let stopInfo: StopInfoDTO?
        let stops: [StopDTO]?
    }

    private struct StopInfoDTO: Decodable {
        let scheduledNext: String?
        let actualNext: String?
        let actualLast: String?
        let finalStationName: String?
    }

    private struct StopDTO: Decodable {
        struct Station: Decodable {
            struct Coordinates: Decodable {
                let latitude: Double?
                let longitude: Double?
            }
            let evaNr: String?
            let name: String?
            let geocoordinates: Coordinates?
        }
        struct Timetable: Decodable {
            let scheduledArrivalTime: Double?
            let actualArrivalTime: Double?
            let arrivalDelay: String?
            let scheduledDepartureTime: Double?
            let actualDepartureTime: Double?
            let departureDelay: String?
        }
        struct Track: Decodable {
            let scheduled: String?
            let actual: String?
        }
        struct Info: Decodable {
            let passed: Bool?
            let distanceFromStart: Double?
        }
        let station: Station?
        let timetable: Timetable?
        let track: Track?
        let info: Info?

        var stop: TrainSnapshot.Stop? {
            guard let id = station?.evaNr?.nilIfEmpty, let name = station?.name?.nilIfEmpty else { return nil }
            let draft = StopDraft(
                name: name, stopID: id,
                latitude: station?.geocoordinates?.latitude ?? 0,
                longitude: station?.geocoordinates?.longitude ?? 0,
                scheduledArrival: ICEPortalClient.date(timetable?.scheduledArrivalTime),
                scheduledDeparture: ICEPortalClient.date(timetable?.scheduledDepartureTime),
                arrival: ICEPortalClient.date(timetable?.actualArrivalTime),
                departure: ICEPortalClient.date(timetable?.actualDepartureTime),
                track: track?.actual?.nilIfEmpty ?? track?.scheduled?.nilIfEmpty)
            return TrainSnapshot.Stop(
                draft: draft, passed: info?.passed ?? false, distanceFromStart: info?.distanceFromStart,
                arrivalDelay: timetable?.arrivalDelay?.nilIfEmpty,
                departureDelay: timetable?.departureDelay?.nilIfEmpty)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
