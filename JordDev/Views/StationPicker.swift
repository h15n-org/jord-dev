// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The station search sheet: results as you type, recent stations, and stations nearby.

import SwiftUI

struct StationPicker: View {
    private enum Nearby {
        case idle, loading, loaded, unavailable
    }

    let title: LocalizedStringKey
    let onPick: (Station) -> Void

    @State private var query = ""
    @State private var recents = RecentStations.all
    @State private var stations: [Station] = []
    @State private var failed = false
    @State private var loadedText: String?
    @FocusState private var isFieldFocused: Bool
    @State private var location = LocationProvider()
    @State private var nearby: [Station] = []
    @State private var nearbyState = Nearby.idle
    @State private var removed: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
        .background(Theme.paper)
        .onAppear { isFieldFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.quiet)
                TextField("Bahnhof", text: $query)
                    .focused($isFieldFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .accessibilityLabel(title)
                if !query.isEmpty {
                    Button("Eingabe löschen", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.quiet)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .card()

            Button("Schließen", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 48)
                .background(Theme.paper, in: .circle)
                .overlay { Circle().strokeBorder(Theme.hairline, lineWidth: 1) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var list: some View {
        Group {
            List {
                if trimmedQuery.count < 2 {
                    recentRows
                    nearbyRows
                }
                ForEach(stations) { station in
                    row(station)
                }
            }
            .paperList()
            .overlay {
                if failed {
                    EmptyState(
                        title: "Suche nicht möglich", systemImage: "wifi.exclamationmark",
                        message: "Die Bahnhöfe konnten nicht geladen werden.", pastel: .coral)
                } else if stations.isEmpty, loadedText == trimmedQuery {
                    EmptyState(
                        title: "Kein Bahnhof gefunden", systemImage: "magnifyingglass",
                        message: "Prüfe die Schreibweise oder suche nach einem anderen Namen.")
                }
            }
            .task {
                if location.isAuthorized { await loadNearby() }
            }
            .task(id: query) {
                let text = query.trimmingCharacters(in: .whitespaces)
                guard text.count >= 2 else {
                    stations = []
                    loadedText = nil
                    return
                }
                // Debounce: Transitous asks clients to go easy on requests.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                do {
                    stations = try await TransitousClient.shared.stations(matching: text)
                    loadedText = text
                    failed = false
                } catch is CancellationError {
                } catch let error as URLError where error.code == .cancelled {
                } catch {
                    failed = true
                }
            }
        }
    }

    @ViewBuilder private var recentRows: some View {
        let shown = recents.filter { !removed.contains($0.id) }
        if !shown.isEmpty {
            Text("Zuletzt")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.quiet)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            ForEach(shown) { station in
                row(station)
                    .swipeActions {
                        Button("Entfernen", systemImage: "trash", role: .destructive) {
                            RecentStations.remove(station)
                            removed.insert(station.id)
                        }
                    }
            }
        }
    }

    @ViewBuilder private var nearbyRows: some View {
        switch nearbyState {
        case .idle where location.status == .notDetermined:
            Button {
                Task { await loadNearby() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .font(.footnote)
                        .foregroundStyle(Pastel.sky.ink)
                        .frame(width: 32, height: 32)
                        .background(Pastel.sky.fill, in: .circle)
                    Text("Bahnhöfe in der Nähe")
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.hairline)
        case .idle, .unavailable:
            if location.status == .denied || location.status == .restricted {
                Text("Für Bahnhöfe in der Nähe kannst du Jord in den Einstellungen den Standort erlauben.")
                    .font(.footnote)
                    .foregroundStyle(Theme.quiet)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        case .loaded:
            Text("In der Nähe")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.quiet)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            ForEach(nearby) { station in
                row(station)
            }
        }
    }

    private func row(_ station: Station) -> some View {
        Button {
            onPick(station)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .foregroundStyle(Theme.ink)
                if let area = station.area {
                    Text(area)
                        .font(.subheadline)
                        .foregroundStyle(Theme.quiet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.hairline)
    }

    private func loadNearby() async {
        nearbyState = .loading
        guard let coordinate = await location.currentCoordinate(),
              let found = try? await TransitousClient.shared.stations(
                  nearLatitude: coordinate.latitude, longitude: coordinate.longitude),
              !found.isEmpty
        else {
            nearbyState = .unavailable
            return
        }
        nearby = found
        nearbyState = .loaded
    }
}
