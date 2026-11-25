// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The second tab: the journal of checked-in rides, newest first, with deleting a ride
// here, on Träwelling, or both.

import SwiftData
import SwiftUI

struct TripsView: View {
    @Query(sort: \Journey.departure, order: .reverse) private var journeys: [Journey]
    @State private var selection: PersistentIdentifier?
    @State private var deleting: Journey?
    @State private var deleteFailure: String?
    @Environment(\.modelContext) private var context
    @Environment(TraewellingActivity.self) private var traewelling

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(journeys) { journey in
                    if let draft = journey.draft {
                        JourneyRow(draft: draft, showsDate: true, isSelected: journey.id == selection)
                            .paperRow()
                    }
                }
                .onDelete { offsets in
                    for journey in offsets.map({ journeys[$0] }) {
                        if Self.isOnTraewelling(journey) {
                            deleting = journey
                        } else {
                            remove(journey)
                        }
                    }
                }
            }
            .paperList()
            .overlay {
                if journeys.isEmpty {
                    EmptyState(
                        title: "Noch keine Reisen", systemImage: "book.pages",
                        message: "Checke unter Abfahrten in eine Fahrt ein, dann erscheint sie hier.", pastel: .lavender)
                }
            }
            .navigationTitle("Meine Reisen")
        } detail: {
            if let journey = journeys.first(where: { $0.id == selection }), let draft = journey.draft {
                JourneyDetailView(
                    draft: draft,
                    push: traewelling.outcome(for: journey),
                    sendToTraewelling: traewelling.canSend(journey) ? { traewelling.send(journey) } : nil,
                    delete: { deleting = journey },
                    endRide: { traewelling.end($0, at: $1, in: journey, among: journeys) })
            } else {
                LogoEmptyState(
                    title: "Keine Reise ausgewählt",
                    message: "Wähle eine Reise aus, um ihre Halte zu sehen.")
            }
        }
        // On the split view, not the list: on a phone the list is off screen while a trip is open.
        .confirmationDialog(
            deleting.map(Self.isOnTraewelling) == true
                ? "Diese Reise ist auch bei Träwelling eingecheckt." : "Diese Reise löschen?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible, presenting: deleting
        ) { journey in
            if Self.isOnTraewelling(journey) {
                Button("Nur in Jord löschen", role: .destructive) { remove(journey) }
                if let client = TraewellingSettings.client {
                    Button("Nur bei Träwelling löschen", role: .destructive) {
                        Task { deleteFailure = await TraewellingPush.delete(journey, client: client) }
                    }
                    Button("In Jord und bei Träwelling löschen", role: .destructive) {
                        Task {
                            if let reason = await TraewellingPush.delete(journey, client: client) {
                                deleteFailure = reason
                            } else {
                                remove(journey)
                            }
                        }
                    }
                }
            } else {
                Button("Reise löschen", role: .destructive) { remove(journey) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { journey in
            if Self.isOnTraewelling(journey) {
                Text("Bei Träwelling gelöschte Check-ins lassen sich nicht wiederherstellen.")
            }
        }
        .alert(
            "Bei Träwelling nicht gelöscht",
            isPresented: Binding(get: { deleteFailure != nil }, set: { if !$0 { deleteFailure = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(deleteFailure ?? "") In Jord wurde nichts gelöscht.")
        }
    }

    private static func isOnTraewelling(_ journey: Journey) -> Bool {
        journey.legs.contains { $0.traewellingStatusID != nil }
    }

    private func remove(_ journey: Journey) {
        if journey.id == selection { selection = nil }
        context.delete(journey)
    }
}
