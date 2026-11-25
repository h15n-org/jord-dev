// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum RecentStations {
    private static let key = "recentStations"
    private static let limit = 10

    static var all: [Station] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stations = try? JSONDecoder().decode([Station].self, from: data)
        else { return [] }
        return stations
    }

    static func record(_ station: Station) {
        var stations = all
        stations.removeAll { same($0, station) }
        stations.insert(station, at: 0)
        save(Array(stations.prefix(limit)))
    }

    static func remove(_ station: Station) {
        save(all.filter { !same($0, station) })
    }

    private static func same(_ first: Station, _ second: Station) -> Bool {
        first.id == second.id || first.name == second.name
    }

    private static func save(_ stations: [Station]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(stations), forKey: key)
    }
}
