// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The app's entry point: three tabs (departures, journal, profile), the shared model of
// the train the phone is on, and the calendar sync that runs alongside them.

import SwiftData
import SwiftUI

@main
struct JordDevApp: App {
    private enum AppTab {
        case board, trips, profile
    }

    @State private var tab = AppTab.board
    @State private var train = LiveTrain()
    @State private var traewelling = TraewellingActivity()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                Tab("Abfahrten", systemImage: "list.bullet", value: AppTab.board) {
                    BoardView()
                }
                Tab("Meine Reisen", systemImage: "book.pages", value: AppTab.trips) {
                    TripsView()
                }
                Tab("Profil", systemImage: "person", value: AppTab.profile) {
                    ProfileView()
                }
            }
            .tint(Theme.ink)
            .environment(train)
            .environment(traewelling)
            .modifier(CalendarKeeper())
            .task(id: scenePhase) {
                if scenePhase == .active { await train.run() }
            }
            .preferredColorScheme(.light)
        }
        .modelContainer(for: Journey.self)
    }
}
