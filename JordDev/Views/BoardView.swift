// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The first tab. Pick a station, open its departures, pick a train and the stop to get
// off at, and check into that ride. Also decides what happens when a new check-in
// overlaps a ride that is still under way.

import SwiftData
import SwiftUI

struct BoardView: View {
    private enum Field: String, Identifiable {
        case station
        case board
        var id: String { rawValue }
    }

    @State private var station: Station?
    /// The departure time that was picked. Nil is now: the board then opens at the moment it is asked for.
    @State private var pickedDate: Date?
    @State private var ride: JourneyDraft?
    @State private var selection: JourneyDraft.ID?
    @State private var picking: Field?
    @State private var checkIns = 0
    @State private var board: Station?
    @State private var boardNext: Station?
    /// The stations offered before a ride is picked.
    @State private var recents = RecentStations.all
    @State private var checkingIn: JourneyDraft?
    @State private var clash: Clash?

    private struct Clash {
        let draft: JourneyDraft
        let journey: Journey
        let ride: LegDraft
        let stops: [StopDraft]?
    }
    @Environment(TraewellingActivity.self) private var traewelling
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var journeys: [Journey]
    @Environment(LiveTrain.self) private var train

    private var checkedIn: Set<String> { Set(journeys.map(\.sourceID)) }
    private var selected: JourneyDraft? { ride.flatMap { $0.id == selection ? $0 : nil } }

    private var journalRide: (journey: Journey, ride: LiveRide)? {
        guard train.snapshot != nil else { return nil }
        let now = Date.now
        return journeys.lazy
            .filter { ICEPortalClient.isReplaying || ($0.departure < now.addingTimeInterval(3600) && $0.arrival > now.addingTimeInterval(-4 * 3600)) }
            .compactMap { journey in
                journey.draft.flatMap { train.ride(of: $0) }.map { (journey, $0) }
            }
            .first
    }

    @ViewBuilder private var liveCard: some View {
        if let snapshot = train.snapshot {
            let current = journalRide
            LiveTrainCard(
                snapshot: snapshot, ride: current?.ride,
                exitHere: current.map { current in { end(current.ride, at: $0, in: current.journey) } })
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Group {
                    brand
                    if sizeClass == .compact {
                        liveCard
                    }
                    form
                    Button {
                        if let station {
                            board = station
                        } else {
                            picking = .board
                        }
                    } label: {
                        Label("Abfahrten", systemImage: "list.bullet")
                    }
                    .buttonStyle(InkButtonStyle())
                }
                .paperRow()
                .selectionDisabled()

                if ride == nil {
                    starts
                }

                ForEach(ride.map { [$0] } ?? []) { draft in
                    JourneyRow(
                        draft: draft, showsDate: false,
                        isSelected: draft.id == selection,
                        isCheckedIn: checkedIn.contains(draft.id)
                    ) {
                        checkIn(draft)
                    }
                    .paperRow()
                }
            }
            .paperList()
            .navigationTitle("Abfahrten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar(sizeClass == .compact ? .hidden : .automatic, for: .navigationBar)
            .sheet(item: $picking, onDismiss: {
                board = boardNext
                boardNext = nil
            }) { field in
                StationPicker(
                    title: field == .station ? "Bahnhof" : "Abfahrten ab"
                ) { picked in
                    station = picked
                    RecentStations.record(picked)
                    recents = RecentStations.all
                    if field == .board { boardNext = picked }
                }
            }
        } detail: {
            if let draft = selected {
                let saved = journeys.first { $0.sourceID == draft.id }
                JourneyDetailView(
                    draft: saved?.draft ?? draft, isCheckedIn: saved != nil,
                    push: saved.flatMap(traewelling.outcome),
                    sendToTraewelling: saved.flatMap { journey in
                        traewelling.canSend(journey) ? { traewelling.send(journey) } : nil
                    },
                    // Named, not trailing: a trailing closure would land on `delete`.
                    checkIn: { checkIn(draft) },
                    endRide: saved.map { journey in { end($0, at: $1, in: journey) } },
                    showsOtherTrain: sizeClass != .compact)
            } else {
                GeometryReader { pane in
                    ScrollView {
                        VStack(spacing: 0) {
                            liveCard
                                .padding(16)
                            LogoEmptyState(
                                title: "Keine Fahrt ausgewählt",
                                message: "Wähle einen Bahnhof, einen Zug und deinen Ausstieg, um die Fahrt zu sehen.")
                        }
                        .frame(minHeight: pane.size.height)
                    }
                }
                .background(Theme.paper)
            }
        }
        .animation(.snappy, value: train.snapshot != nil)
        .sensoryFeedback(.success, trigger: checkIns)
        .alert(
            "Du bist noch in \(clash?.ride.lineName ?? "") nach \(clash?.ride.destination.name ?? "") eingecheckt.",
            isPresented: Binding(get: { clash != nil }, set: { if !$0 { clash = nil } }), presenting: clash
        ) { clash in
            if let stops = clash.stops, let exit = stops.last {
                Button("In \(exit.name) ausgestiegen") { leaveAndCheckIn(clash, stops: stops) }
            }
            Button("Trotzdem einchecken") { start(clash.draft, heldBy: clash) }
            Button("Abbrechen", role: .cancel) {}
        } message: { clash in
            if let exit = clash.stops?.last {
                if clash.ride.traewellingStatusID != nil {
                    Text("Wenn du in \(exit.name) ausgestiegen bist, endet \(clash.ride.lineName) dort, auch bei Träwelling.")
                } else {
                    Text("Wenn du in \(exit.name) ausgestiegen bist, endet \(clash.ride.lineName) dort.")
                }
            } else if clash.ride.traewellingStatusID != nil {
                Text("Die neue Fahrt kommt ins Reisetagebuch. An Träwelling geht sie erst, wenn die alte Fahrt korrigiert ist.")
            } else {
                Text("Die neue Fahrt beginnt, bevor die alte endet.")
            }
        }
        .sheet(item: $board) { station in
            DepartureBoardSheet(
                station: station, time: max(pickedDate ?? .now, .now.addingTimeInterval(-120))
            ) { journey in
                ride = journey
                selection = journey.id
            }
        }
        .sheet(item: $checkingIn) { draft in
            CheckInSheet(draft: draft) { visibility in
                save(draft, visibility: visibility)
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 12) {
            Image(.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text(verbatim: "Jord \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")")
                .font(.system(size: 40, weight: .medium, design: .serif))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var form: some View {
        VStack(spacing: 0) {
            Button {
                picking = .station
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Von")
                        .font(.caption)
                        .foregroundStyle(Theme.quiet)
                    Text(station?.name ?? String(localized: "Bahnhof wählen"))
                        .font(.body.weight(station == nil ? .regular : .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Hairline()
            departureField
        }
        .card()
    }

    /// The departure time. It runs along with the clock until one is picked; "Jetzt" lets go of
    /// the picked one again.
    private var departureField: some View {
        TimelineView(.everyMinute) { clock in
            HStack(spacing: 8) {
                Text("Abfahrt")
                Spacer()
                if pickedDate != nil {
                    Button("Jetzt") { pickedDate = nil }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 1) }
                        .contentShape(.capsule)
                        .buttonStyle(.plain)
                }
                DatePicker("Abfahrt", selection: Binding(
                    get: { pickedDate ?? clock.date },
                    set: { pickedDate = $0 }))
                    .labelsHidden()
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    /// Where the latest journey that has set off ends, unless the stations used lately
    /// already offer it.
    private var lastDestination: StopDraft? {
        let now = Date.now
        let stop = journeys.filter { $0.departure <= now }.max { $0.arrival < $1.arrival }?
            .legs.max { $0.index < $1.index }?.draft?.destination
        guard let stop, !recents.prefix(4).contains(where: { $0.name == stop.name }) else { return nil }
        return stop
    }

    /// What the page offers before a ride is picked: the stations used lately and the ones
    /// nearby, each one tap from its departures.
    @ViewBuilder private var starts: some View {
        if !recents.isEmpty {
            StartCard(title: "Zuletzt", items: Array(recents.prefix(4)), onPick: open, onRemove: { station in
                RecentStations.remove(station)
                recents = RecentStations.all
            }) { station in
                StationLabel(station: station)
            }
            .paperRow()
            .selectionDisabled()
        }
        NearbyStarts(lastDestination: lastDestination, onPick: open)
            .paperRow()
            .selectionDisabled()
    }

    /// Makes a station the one in the form and shows what leaves from it.
    private func open(_ picked: Station) {
        station = picked
        RecentStations.record(picked)
        recents = RecentStations.all
        board = picked
    }

    private func checkIn(_ draft: JourneyDraft) {
        guard !checkedIn.contains(draft.id) else { return }
        let near = journeys.filter { $0.departure < draft.arrival && $0.arrival > draft.departure }
        let clashes = near.compactMap { journey in
            journey.rideOverlapping(draft).map { Clash(draft: draft, journey: journey, ride: $0.ride, stops: $0.stops) }
        }
        if let found = clashes.first(where: { $0.stops != nil }) ?? clashes.first {
            clash = found
            return
        }
        start(draft, heldBy: nil)
    }

    private func start(_ draft: JourneyDraft, heldBy clash: Clash?) {
        guard !checkedIn.contains(draft.id) else { return }
        guard TraewellingSettings.client != nil else {
            save(draft, visibility: nil)
            return
        }
        if let clash, clash.ride.traewellingStatusID != nil, TraewellingSettings.mode != .never {
            if let journey = save(draft, visibility: nil) {
                TraewellingPush.hold(journey, behind: clash.ride)
            }
            return
        }
        switch TraewellingSettings.mode {
        case .ask: checkingIn = draft
        case .automatic: save(draft, visibility: TraewellingSettings.visibility)
        case .never: save(draft, visibility: nil)
        }
    }

    private func leaveAndCheckIn(_ clash: Clash, stops: [StopDraft]) {
        Task {
            await traewelling.end(clash.ride, stops: stops, in: clash.journey)
            start(clash.draft, heldBy: nil)
        }
    }

    @discardableResult
    private func save(_ draft: JourneyDraft, visibility: Int?) -> Journey? {
        guard !checkedIn.contains(draft.id) else { return nil }
        let journey = Journey(draft)
        context.insert(journey)
        checkIns += 1
        if let visibility { traewelling.send(journey, visibility: visibility) }
        return journey
    }

    private func end(_ ride: LiveRide, at stop: TrainSnapshot.Stop, in journey: Journey) {
        traewelling.end(ride, at: stop, in: journey, among: journeys)
    }
}
