// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The card shown on a train's Wi-Fi: speed, next stop, distance to the traveller's stop,
// and the offer to end the ride where the train is.

import SwiftUI

struct LiveTrainCard: View {
    let snapshot: TrainSnapshot
    let ride: LiveRide?
    var exitHere: ((TrainSnapshot.Stop) -> Void)?
    @State private var exiting: TrainSnapshot.Stop?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Pastel.onTime.ink)
                        .frame(width: 7, height: 7)
                    Text("Live aus dem Zug")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Pastel.onTime.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Pastel.onTime.fill, in: .capsule)
                .accessibilityElement(children: .combine)

                Spacer()

                if let train = trainText {
                    Text(train)
                        .font(.caption)
                        .foregroundStyle(Theme.quiet)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack(alignment: .firstTextBaseline) {
                if let speed = snapshot.speed {
                    Text(verbatim: "\(Int(speed.rounded())) km/h")
                        .font(.system(.largeTitle, design: .serif, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(Int(speed.rounded())) Kilometer pro Stunde")
                }
                Spacer()
                if let ride, let distance = ride.distanceToDestination {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("noch \(Self.distance(distance))")
                            .font(.headline)
                            .monospacedDigit()
                        Text("bis \(ride.alight.draft.name)")
                            .font(.footnote)
                            .foregroundStyle(Theme.quiet)
                    }
                    .accessibilityElement(children: .combine)
                } else if ride == nil, let line = snapshot.lineName {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(line)
                            .font(.headline)
                        if let final = snapshot.finalStationName {
                            Text("nach \(final)")
                                .font(.footnote)
                                .foregroundStyle(Theme.quiet)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            if let progress = ride?.progress {
                ProgressView(value: progress)
                    .tint(Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .accessibilityLabel("Fahrt")
            }

            if let stop = snapshot.currentStop {
                Hairline()
                stopRow("Halt in", stop: stop, time: stop.draft.departure ?? stop.draft.scheduledDeparture,
                        delay: stop.departureDelay, timeLabel: "ab", note: nil)
            } else if let stop = snapshot.nextStop {
                Hairline()
                stopRow("Nächster Halt", stop: stop, time: stop.draft.arrival ?? stop.draft.scheduledArrival,
                        delay: stop.arrivalDelay, timeLabel: "an",
                        note: snapshot.distanceToNextStop.map { String(localized: "noch \(Self.distance($0))") })
            }

            if let ride, ride.isBeforeDestination, ride.alight.id != (snapshot.currentStop ?? snapshot.nextStop)?.id {
                Hairline()
                stopRow("Dein Ausstieg", stop: ride.alight,
                        time: ride.alight.draft.arrival ?? ride.alight.draft.scheduledArrival,
                        delay: ride.alight.arrivalDelay, timeLabel: "an", note: nil)
            }

            if exitHere != nil, let stop = ride?.otherExit {
                Hairline()
                Button {
                    exiting = stop
                } label: {
                    Label(
                        snapshot.currentStop != nil
                            ? String(localized: "Hier aussteigen")
                            : String(localized: "In \(stop.draft.name) aussteigen"),
                        systemImage: "figure.walk.departure")
                }
                .buttonStyle(OutlineButtonStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .confirmationDialog(
            "In \(exiting?.draft.name ?? "") aussteigen?",
            isPresented: Binding(get: { exiting != nil }, set: { if !$0 { exiting = nil } }),
            titleVisibility: .visible, presenting: exiting
        ) { stop in
            Button("Fahrt hier beenden") { exitHere?(stop) }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            if ride?.leg.traewellingStatusID != nil {
                Text("Die Fahrt endet dann an diesem Halt, auch bei Träwelling.")
            } else {
                Text("Die Fahrt endet dann an diesem Halt.")
            }
        }
        .background(Pastel.onTime.fill.opacity(0.4), in: shape)
        .background(Theme.paper, in: shape)
        .overlay { shape.strokeBorder(Pastel.onTime.ink.opacity(0.55), lineWidth: 1.5) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
    }

    private var trainText: String? {
        let kind = snapshot.series.map { Self.kinds[$0] ?? String(localized: "Baureihe \($0)") }
        let trainset = snapshot.trainset.flatMap { name -> String? in
            guard let number = Int(name.drop { !$0.isNumber }) else { return nil }
            return String(localized: "Tz \(String(number))")
        }
        let parts = [kind, trainset].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let kinds = [
        "401": "ICE 1", "402": "ICE 2", "403": "ICE 3", "406": "ICE 3", "407": "ICE 3",
        "408": "ICE 3neo", "411": "ICE T", "412": "ICE 4", "415": "ICE T",
    ]

    private func stopRow(
        _ title: LocalizedStringKey, stop: TrainSnapshot.Stop, time: Date?, delay: String?,
        timeLabel: LocalizedStringKey, note: String?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.quiet)
                Text(stop.draft.name)
                    .font(.body.weight(.semibold))
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.quiet)
                        .monospacedDigit()
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let time {
                        Text(timeLabel)
                            .font(.footnote)
                            .foregroundStyle(Theme.quiet)
                        Text(time, format: .dateTime.hour().minute())
                            .monospacedDigit()
                    }
                    if let minutes = delay.flatMap({ Int($0) }), minutes != 0 {
                        DelayChip(minutes: minutes)
                    }
                }
                if let track = stop.draft.track {
                    Text("Gl. \(track)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.quiet)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private static func distance(_ metres: Double) -> String {
        if metres < 1000 {
            return Measurement(value: (metres / 100).rounded() * 100, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided))
        }
        return Measurement(value: metres / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(
                width: .abbreviated, usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(metres < 100_000 ? 1 : 0))))
    }
}
