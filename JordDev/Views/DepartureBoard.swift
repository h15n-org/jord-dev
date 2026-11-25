// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The departure board as a sheet: the next trains from one station, filtered by kind of
// train, and the page that lists a train's stops to choose where to get off.

import SwiftUI

struct DepartureBoardSheet: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, longDistance, regional

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .all: "Alle"
            case .longDistance: "Fernverkehr"
            case .regional: "Regional"
            }
        }

        var modes: String {
            switch self {
            case .all: "HIGHSPEED_RAIL,LONG_DISTANCE,NIGHT_RAIL,REGIONAL_RAIL,REGIONAL_FAST_RAIL,SUBURBAN"
            case .longDistance: "HIGHSPEED_RAIL,LONG_DISTANCE,NIGHT_RAIL"
            case .regional: "REGIONAL_RAIL,REGIONAL_FAST_RAIL,SUBURBAN"
            }
        }
    }

    private enum Phase {
        case loading, loaded, failed
    }

    let station: Station
    let onPick: (JourneyDraft) -> Void

    @State private var time: Date
    @State private var filter = Filter.all
    @State private var hasLoaded = false
    @State private var board = DepartureBoard(departures: [])
    @State private var phase = Phase.loading
    @State private var isLoadingEarlier = false
    @State private var isLoadingLater = false
    @State private var path: [Departure.ID] = []
    @Environment(\.dismiss) private var dismiss

    init(station: Station, time: Date, onPick: @escaping (JourneyDraft) -> Void) {
        self.station = station
        self.onPick = onPick
        _time = State(initialValue: time)
    }

    private struct Request: Equatable {
        let time: Date
        let filter: Filter
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Group {
                    controls
                    rows
                }
                .paperRow()
            }
            .paperList()
            .navigationTitle(station.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(for: Departure.ID.self) { id in
                if let departure = board.departures.first(where: { $0.id == id }) {
                    TrainStopsPage(departure: departure) { journey in
                        onPick(journey)
                        dismiss()
                    }
                }
            }
            .task(id: Request(time: time, filter: filter)) { await load() }
        }
        .presentationBackground(Theme.paper)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            Picker("Züge", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Hairline()
            DatePicker("Abfahrt ab", selection: $time)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .card()
    }

    @ViewBuilder private var rows: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        case .failed:
            EmptyState(
                title: "Keine Verbindung zum Fahrplan", systemImage: "wifi.exclamationmark",
                message: "Die Abfahrten konnten nicht geladen werden.", pastel: .coral)
        case .loaded where board.departures.isEmpty:
            EmptyState(
                title: "Keine Abfahrten gefunden", systemImage: "questionmark",
                message: "Versuche eine andere Zeit oder andere Züge.")
        case .loaded:
            if board.earlier != nil {
                pageButton("Frühere Abfahrten", systemImage: "chevron.up", isLoading: isLoadingEarlier) {
                    await loadPage(earlier: true)
                }
            }
            ForEach(board.departures) { departure in
                // A button, not a link: a link would put its arrow outside the card.
                Button {
                    path.append(departure.id)
                } label: {
                    DepartureRow(departure: departure)
                }
                .buttonStyle(.plain)
                .disabled(departure.isCancelled)
            }
            if board.later != nil {
                pageButton("Spätere Abfahrten", systemImage: "chevron.down", isLoading: isLoadingLater) {
                    await loadPage(earlier: false)
                }
            }
        }
    }

    private func pageButton(
        _ title: LocalizedStringKey, systemImage: String, isLoading: Bool, action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            if isLoading {
                ProgressView()
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .buttonStyle(OutlineButtonStyle())
    }

    private func load() async {
        // Debounce: Transitous asks clients to go easy on requests, and the date picker
        // passes through many values on the way. Fixing this.
        if hasLoaded {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
        }
        hasLoaded = true
        phase = .loading
        do {
            board = try await TransitousClient.shared.departures(from: station, time: time, modes: filter.modes)
            phase = .loaded
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            board = DepartureBoard(departures: [])
            phase = .failed
        }
    }

    private func loadPage(earlier: Bool) async {
        guard let cursor = earlier ? board.earlier : board.later, !isLoadingEarlier, !isLoadingLater else { return }
        if earlier { isLoadingEarlier = true } else { isLoadingLater = true }
        defer {
            isLoadingEarlier = false
            isLoadingLater = false
        }
        guard let page = try? await TransitousClient.shared.departures(
            from: station, time: time, modes: filter.modes, cursor: cursor)
        else { return }
        let known = Set(board.departures.map(\.id))
        let new = page.departures.filter { !known.contains($0.id) }
        if earlier {
            board.departures = new + board.departures
            board.earlier = page.earlier
        } else {
            board.departures += new
            board.later = page.later
        }
    }
}

private struct DepartureRow: View {
    let departure: Departure

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(departure.time, format: .dateTime.hour().minute())
                    .font(.headline)
                    .monospacedDigit()
                    .strikethrough(departure.isCancelled)
                if let delay = departure.stop.delayMinutes, !departure.isCancelled {
                    DelayChip(minutes: delay)
                }
            }
            .frame(minWidth: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                LineChip(departure: departure)
                if let headsign = departure.headsign {
                    Text(headsign)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
                if departure.isCancelled {
                    Text("Fällt aus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Pastel.delayed.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let track = departure.stop.track {
                Text("Gl. \(track)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.quiet)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .card()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct TrainStopsPage: View {
    let departure: Departure
    let onPick: (JourneyDraft) -> Void

    @State private var run: TrainRun?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    LineChip(departure: departure)
                    Text("Wo steigst du aus?")
                        .font(.title3.weight(.bold))
                    Text("ab \(departure.stop.name), \(departure.time, format: .dateTime.hour().minute())")
                        .font(.subheadline)
                        .foregroundStyle(Theme.quiet)
                }
                .padding(.horizontal, 4)

                if let run {
                    let stops = run.stops(after: departure)
                    if stops.isEmpty {
                        EmptyState(
                            title: "Keine weiteren Halte", systemImage: "questionmark",
                            message: "Dieser Zug endet hier.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                                if index > 0 { Hairline() }
                                Button {
                                    if let journey = run.journey(from: departure, to: stop) { onPick(journey) }
                                } label: {
                                    stopRow(stop)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .card()
                    }
                } else if failed {
                    EmptyState(
                        title: "Keine Verbindung zum Fahrplan", systemImage: "wifi.exclamationmark",
                        message: "Die Halte konnten nicht geladen werden.", pastel: .coral)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
        }
        .background(Theme.paper)
        .navigationTitle(departure.lineName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard run == nil else { return }
            do {
                run = try await TransitousClient.shared.run(of: departure)
                failed = run == nil
            } catch {
                failed = true
            }
        }
    }

    private func stopRow(_ stop: StopDraft) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Group {
                if let time = stop.scheduledArrival ?? stop.arrival {
                    Text(time, format: .dateTime.hour().minute())
                } else {
                    Text(verbatim: "–")
                }
            }
            .monospacedDigit()
            .frame(minWidth: 52, alignment: .leading)
            Text(stop.name)
                .multilineTextAlignment(.leading)
            if let delay = stop.delayMinutes {
                DelayChip(minutes: delay)
            }
            Spacer(minLength: 12)
            if let track = stop.track {
                Text("Gl. \(track)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.quiet)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
