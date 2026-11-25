// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CheckInSheet: View {
    let draft: JourneyDraft
    let onCheckIn: (Int?) -> Void

    @State private var visibility = TraewellingSettings.visibility
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Einchecken")
                    .font(.title3.weight(.bold))
                Text("\(draft.origin.name) → \(draft.destination.name)")
                    .foregroundStyle(Theme.quiet)
            }
            .padding(.bottom, 4)

            HStack {
                Text("Sichtbarkeit bei Träwelling")
                Spacer(minLength: 12)
                Picker("Sichtbarkeit bei Träwelling", selection: $visibility) {
                    ForEach(TraewellingSettings.visibilities, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                .labelsHidden()
                .tint(Theme.ink)
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .card()

            both.buttonStyle(InkButtonStyle())
            journalOnly.buttonStyle(OutlineButtonStyle())
        }
        .foregroundStyle(Theme.ink)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationBackground(Theme.paper)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }

    private var both: some View {
        Button("Einchecken + Träwelling", systemImage: "arrow.up.circle") {
            onCheckIn(visibility)
            dismiss()
        }
    }

    private var journalOnly: some View {
        Button("Nur in Jord einchecken", systemImage: "plus") {
            onCheckIn(nil)
            dismiss()
        }
    }
}
