// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// What the first page offers before a station is picked: cards of one-tap starts, the
// stations nearby and where the last journey ended.

import CoreLocation
import SwiftUI

/// A heading with a card of rows under it, each row one tap away from a result. This is what
/// the first page shows while nothing has been searched yet.
struct StartCard<Item: Identifiable, Row: View>: View {
    let title: LocalizedStringKey
    let items: [Item]
    let onPick: (Item) -> Void
    /// Given, a long press on a row offers to remove it.
    var onRemove: ((Item) -> Void)?
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.quiet)
                .padding(.leading, 16)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    if item.id != items.first?.id {
                        Hairline()
                    }
                    Button {
                        onPick(item)
                    } label: {
                        row(item)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if let onRemove {
                            Button("Entfernen", systemImage: "trash", role: .destructive) {
                                onRemove(item)
                            }
                        }
                    }
                }
            }
            .card()
        }
        .padding(.top, 10)
    }
}

/// A station's name over the town it is in.
struct StationLabel: View {
    let station: Station

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(station.name)
                .foregroundStyle(Theme.ink)
            if let area = station.area {
                Text(area)
                    .font(.subheadline)
                    .foregroundStyle(Theme.quiet)
            }
        }
    }
}

/// The stations closest to where the user is, with how far each one is. Looks them up by
/// itself once the location is allowed, and again whenever the app comes back to the front.
/// Before the user has decided, it is one button that asks; after a no, it shows nothing.
///
/// Above them goes where the last journey ended, which is most likely where the next one
/// starts, unless that station is among the nearby ones anyway.
struct NearbyStarts: View {
    /// Where the last journey ended.
    var lastDestination: StopDraft?
    let onPick: (Station) -> Void

    private struct Found: Identifiable {
        let station: Station
        let metres: Double
        var id: String { station.id }
    }

    private struct Destination: Identifiable {
        let stop: StopDraft
        var id: String { stop.name }
    }

    @State private var location = LocationProvider()
    @State private var found: [Found] = []
    @State private var isLoading = false
    /// Whether the nearby stations were asked for; until then nobody knows what to leave out.
    @State private var didLoad = false
    @State private var isResolving = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // A stack even when empty, so the task below always has something to hang on.
        VStack(spacing: 0) {
            if let stop = shownDestination {
                StartCard(title: "Letztes Ziel", items: [Destination(stop: stop)], onPick: { item in
                    Task { await pick(item.stop) }
                }) { item in
                    Text(item.stop.name)
                        .foregroundStyle(Theme.ink)
                }
                .disabled(isResolving)
            }
            if !found.isEmpty {
                StartCard(title: "In der Nähe", items: found, onPick: { onPick($0.station) }) { item in
                    HStack(spacing: 12) {
                        StationLabel(station: item.station)
                        Spacer(minLength: 0)
                        Text(Measurement(value: item.metres, unit: UnitLength.meters),
                             format: .measurement(width: .abbreviated, usage: .road))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.quiet)
                    }
                }
            } else if location.status == .notDetermined {
                Button("Bahnhöfe in der Nähe", systemImage: "location") {
                    Task { await load() }
                }
                .buttonStyle(OutlineButtonStyle())
                .disabled(isLoading)
                .padding(.top, 10)
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active, location.isAuthorized { await load() }
        }
    }

    /// The last destination, when it is worth its own card: not while the nearby stations
    /// are still on their way, and not when one of them is the same place.
    private var shownDestination: StopDraft? {
        guard let stop = lastDestination, didLoad || !location.isAuthorized else { return nil }
        let place = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
        let isNearby = found.contains { item in
            item.station.id == stop.stopID || item.station.name == stop.name
                || place.distance(from: CLLocation(
                    latitude: item.station.latitude, longitude: item.station.longitude)) < 400
        }
        return isNearby ? nil : stop
    }

    /// A journey's stop can come from Träwelling, a ticket or the train's own Wi-Fi, with an ID
    /// the timetable does not know. So the station is looked up by name, and the match closest
    /// to the stop is taken. Without one, the stop goes on as it is.
    private func pick(_ stop: StopDraft) async {
        isResolving = true
        defer { isResolving = false }
        let place = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
        func distance(_ station: Station) -> Double {
            place.distance(from: CLLocation(latitude: station.latitude, longitude: station.longitude))
        }
        let matches = (try? await TransitousClient.shared.stations(matching: stop.name)) ?? []
        if let nearest = matches.min(by: { distance($0) < distance($1) }), distance(nearest) < 2000 {
            onPick(nearest)
        } else if !stop.stopID.isEmpty {
            onPick(Station(
                id: stop.stopID, name: stop.name, area: nil,
                latitude: stop.latitude, longitude: stop.longitude))
        } else if let first = matches.first {
            onPick(first)
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            didLoad = true
        }
        guard let coordinate = await location.currentCoordinate(),
              let stations = try? await TransitousClient.shared.stations(
                  nearLatitude: coordinate.latitude, longitude: coordinate.longitude)
        else { return }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        found = stations.prefix(3).map { station in
            Found(station: station, metres: here.distance(
                from: CLLocation(latitude: station.latitude, longitude: station.longitude)))
        }
    }
}
