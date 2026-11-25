// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Shared views for a ride: the list card, the detail page with its stops, the line and
// delay chips, and the note on whether the check-in reached Träwelling.

import SwiftUI

struct JourneyRow: View {
    let draft: JourneyDraft
    let showsDate: Bool
    var isSelected = false
    var isCheckedIn = false
    var checkIn: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if showsDate {
                    Text("\(draft.origin.name) → \(draft.destination.name)")
                        .font(.headline)
                    Text(draft.departure, format: .dateTime.weekday().day().month().year())
                        .font(.subheadline)
                        .foregroundStyle(Theme.quiet)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        times
                        Spacer(minLength: 12)
                        summaryText
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        times
                        summaryText
                    }
                }
                LineChips(legs: draft.legs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let checkIn {
                Button(
                    isCheckedIn ? "Eingecheckt" : "Einchecken",
                    systemImage: isCheckedIn ? "checkmark.circle.fill" : "plus.circle",
                    action: checkIn
                )
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(isCheckedIn ? Pastel.onTime.ink : Theme.ink)
                .buttonStyle(.borderless)
                .disabled(isCheckedIn)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .card(isSelected: isSelected)
    }

    private var times: some View {
        Text("\(draft.departure, format: .dateTime.hour().minute()) – \(draft.arrival, format: .dateTime.hour().minute())")
            .font(showsDate ? .subheadline : .headline)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var summaryText: some View {
        Text(summary)
            .font(.subheadline)
            .foregroundStyle(Theme.quiet)
            .lineLimit(1)
    }

    private var summary: String {
        Duration.seconds(draft.arrival.timeIntervalSince(draft.departure))
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

struct LineChip: View {
    let lineName: String
    let symbolName: String
    let category: TransitCategory

    init(leg: LegDraft) {
        lineName = leg.lineName
        symbolName = leg.symbolName
        category = leg.category
    }

    init(departure: Departure) {
        lineName = departure.lineName
        symbolName = "train.side.front.car"
        category = departure.category
    }

    var body: some View {
        let pastel = category.pastel
        HStack(spacing: 4) {
            Image(systemName: symbolName)
            Text(lineName)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(pastel.ink)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(pastel.fill, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

struct LineChips: View {
    let legs: [LegDraft]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(legs) { LineChip(leg: $0) }
        }
    }
}

struct JourneyDetailView: View {
    let draft: JourneyDraft
    var isCheckedIn = false
    var push: TraewellingPush.Outcome?
    var sendToTraewelling: (() -> Void)?
    var delete: (() -> Void)?
    var checkIn: (() -> Void)?
    var endRide: ((LiveRide, TrainSnapshot.Stop) -> Void)?
    var showsOtherTrain = false
    @Environment(LiveTrain.self) private var train

    private var live: LiveRide? { train.ride(of: draft) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                JourneyHeader(draft: draft)
                    .padding(.bottom, 4)

                if let checkIn {
                    if isCheckedIn {
                        Label("Eingecheckt", systemImage: "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Pastel.onTime.ink)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Pastel.onTime.fill, in: .capsule)
                    } else {
                        Button("Einchecken", systemImage: "plus", action: checkIn)
                            .buttonStyle(InkButtonStyle())
                    }
                }

                if let push {
                    PushNote(outcome: push)
                }
                if let sendToTraewelling, push != .sending, isCheckedIn || checkIn == nil {
                    Button("An Träwelling senden", systemImage: "arrow.up.circle", action: sendToTraewelling)
                        .buttonStyle(OutlineButtonStyle())
                }

                if let live {
                    LiveTrainCard(
                        snapshot: live.snapshot, ride: live,
                        exitHere: endRide.map { end in { end(live, $0) } })
                } else if showsOtherTrain, let snapshot = train.snapshot {
                    LiveTrainCard(snapshot: snapshot, ride: nil)
                }

                ForEach(draft.legs) { leg in
                    LegCard(leg: leg)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
        }
        .background(Theme.paper)
        .navigationTitle(draft.destination.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let delete {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reise löschen", systemImage: "trash", action: delete)
                }
            }
        }
        .animation(.snappy, value: train.snapshot != nil)
    }
}

private struct JourneyHeader: View {
    let draft: JourneyDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                end(draft.origin, time: draft.departure, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 8)
                    .accessibilityHidden(true)
                end(draft.destination, time: draft.arrival, alignment: .trailing)
            }
            Text(draft.departure, format: .dateTime.weekday(.wide).day().month(.wide).year())
                .foregroundStyle(Theme.quiet)
        }
    }

    private func end(_ stop: StopDraft, time: Date, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(time, format: .dateTime.hour().minute())
                    .font(.system(.title, design: .serif, weight: .medium))
                    .monospacedDigit()
                if let delay = stop.delayMinutes {
                    DelayChip(minutes: delay)
                }
            }
            Text(stop.name)
                .font(.headline)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .combine)
    }
}

struct DelayChip: View {
    let minutes: Int

    var body: some View {
        let pastel = minutes > 0 ? Pastel.delayed : Pastel.onTime
        Text(verbatim: minutes > 0 ? "+\(minutes)" : "\(minutes)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(pastel.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(pastel.fill, in: .capsule)
            .accessibilityLabel(minutes > 0 ? "\(minutes) Minuten später" : "\(-minutes) Minuten früher")
    }
}

private struct PushNote: View {
    let outcome: TraewellingPush.Outcome

    var body: some View {
        switch outcome {
        case .sending:
            Label("Wird an Träwelling gesendet …", systemImage: "arrow.up.circle")
                .font(.footnote)
                .foregroundStyle(Theme.quiet)
        case .sent:
            Label("Bei Träwelling eingecheckt", systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(Pastel.onTime.ink)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Pastel.delayed.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Pastel.delayed.fill, in: .rect(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct LegCard: View {
    let leg: LegDraft
    @State private var showsStops = false
    @State private var showsLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LineChip(leg: leg)
                if let headsign = leg.headsign {
                    Text("Richtung \(headsign)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.quiet)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Hairline()
            StopRow(stop: leg.origin, time: leg.origin.scheduledDeparture, emphasized: true)

            if !leg.intermediateStops.isEmpty {
                Hairline()
                Button {
                    withAnimation(.snappy) { showsStops.toggle() }
                } label: {
                    HStack {
                        Text(leg.intermediateStops.count == 1
                            ? String(localized: "1 Zwischenhalt")
                            : String(localized: "\(leg.intermediateStops.count) Zwischenhalte"))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showsStops ? 180 : 0))
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsStops {
                    ForEach(Array(leg.intermediateStops.enumerated()), id: \.offset) { _, stop in
                        StopRow(
                            stop: stop, time: stop.scheduledDeparture ?? stop.scheduledArrival,
                            emphasized: false)
                    }
                }
            }

            Hairline()
            StopRow(stop: leg.destination, time: leg.destination.scheduledArrival, emphasized: true)

            if let agency = leg.agencyName {
                Hairline()
                Text(agency)
                    .font(.caption)
                    .foregroundStyle(Theme.quiet)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }

            if let statusID = leg.traewellingStatusID,
               let url = URL(string: "https://traewelling.de/status/\(statusID)") {
                Hairline()
                Link(destination: url) {
                    HStack {
                        Text("Bei Träwelling ansehen")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
            }

            if !leg.traewellingLog.isEmpty {
                Hairline()
                Button {
                    withAnimation(.snappy) { showsLog.toggle() }
                } label: {
                    HStack {
                        Text("Träwelling-Protokoll")
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showsLog ? 180 : 0))
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.quiet)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsLog {
                    ForEach(leg.traewellingLog.reversed()) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.date, format: .dateTime.day().month().hour().minute())
                                .font(.caption)
                                .foregroundStyle(Theme.quiet)
                                .monospacedDigit()
                            Text(event.text)
                                .font(.footnote)
                                .foregroundStyle(event.failed ? Pastel.delayed.ink : Theme.ink)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .accessibilityElement(children: .combine)
                    }
                    Color.clear.frame(height: 6)
                }
            }
        }
        .card()
    }
}

private struct StopRow: View {
    let stop: StopDraft
    let time: Date?
    let emphasized: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Group {
                if let time {
                    Text(time, format: .dateTime.hour().minute())
                } else {
                    Text(verbatim: "–")
                }
            }
            .monospacedDigit()
            .frame(minWidth: 52, alignment: .leading)

            Text(stop.name)
                .fontWeight(emphasized ? .semibold : .regular)

            if let delay = stop.delayMinutes {
                DelayChip(minutes: delay)
            }

            Spacer()

            if let track = stop.track {
                Text("Gl. \(track)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.quiet)
            }
        }
        .font(emphasized ? .body : .subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, emphasized ? 12 : 8)
        .accessibilityElement(children: .combine)
    }
}
