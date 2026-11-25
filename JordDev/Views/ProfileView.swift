// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The third tab: a list of settings sections, each with a page of its own, and the
// about page.

import SwiftUI

enum ProfileSection: String, CaseIterable, Identifiable {
    case traewelling, calendar, help, about

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .traewelling: "Träwelling"
        case .calendar: "Kalender"
        case .help: "Hilfe und FAQ"
        case .about: "Über Jord"
        }
    }

    var symbolName: String {
        switch self {
        case .traewelling: "arrow.triangle.2.circlepath"
        case .calendar: "calendar"
        case .help: "questionmark.circle"
        case .about: "info.circle"
        }
    }
}

struct ProfileView: View {
    @AppStorage("traewellingUsername") private var username = ""
    @AppStorage(CalendarSettings.enabledKey) private var calendarOn = false
    @AppStorage(CalendarSettings.calendarKey) private var calendarID = ""
    @State private var selection: ProfileSection?
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var shown: ProfileSection? {
        selection ?? (sizeClass == .compact ? nil : .traewelling)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(ProfileSection.allCases) { section in
                    ProfileRow(
                        section: section, value: value(of: section),
                        isSelected: section == shown, showsChevron: sizeClass == .compact)
                        .paperRow()
                }
            }
            .paperList()
            .navigationTitle("Profil")
        } detail: {
            switch shown ?? .traewelling {
            case .traewelling: TraewellingPage()
            case .calendar: CalendarPage()
            case .help: HelpPage()
            case .about: AboutPage()
            }
        }
    }

    private func value(of section: ProfileSection) -> String {
        switch section {
        case .traewelling: username.isEmpty ? String(localized: "Nicht verbunden") : "@\(username)"
        case .calendar: calendarOn && CalendarSync.hasAccess
            ? CalendarSync.chosen?.title ?? String(localized: "Ein") : String(localized: "Aus")
        case .help: String(localized: "Einchecken, Träwelling, Kalender")
        case .about: String(localized: "Version \(AboutPage.version)")
        }
    }
}

private struct ProfileRow: View {
    let section: ProfileSection
    let value: String
    let isSelected: Bool
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbolName)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .fontWeight(.semibold)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Theme.quiet)
            }
            Spacer(minLength: 12)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(isSelected: isSelected)
        .accessibilityElement(children: .combine)
    }
}

struct ProfilePage<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
        }
        .background(Theme.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutPage: View {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }

    var body: some View {
        ProfilePage(title: "Über Jord") {
            VStack(spacing: 4) {
                Image(.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .accessibilityHidden(true)
                Text(verbatim: "Jord Dev")
                    .font(.system(size: 40, weight: .medium, design: .serif))
                Text("Version \(Self.version)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.quiet)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 0) {
                Text("Daten")
                    .font(.caption)
                    .foregroundStyle(Theme.quiet)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Hairline()
                source("Fahrplan und Echtzeit", credit: "Transitous und seine Datenquellen",
                       link: URL(string: "https://transitous.org/sources/"))
                Hairline()
                source("Geodaten", credit: "© OpenStreetMap-Mitwirkende",
                       link: URL(string: "https://www.openstreetmap.org/copyright"))
                Hairline()
                source("Check-ins", credit: "Träwelling", link: URL(string: "https://traewelling.de"))
                Hairline()
                source("Live aus dem Zug", credit: "WIFIonICE, das Portal im Zug")
            }
            .card()

            VStack(alignment: .leading, spacing: 0) {
                Text("Jord ist Norwegisch für Erde oder Boden und in Asgard der Name der Mutter von Meili, „Reise“.")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Hairline()
                source("Von", credit: "© 2026 Mikka Luster · mikka@h15n.org",
                       link: URL(string: "mailto:mikka@h15n.org"))
                Hairline()
                source("Website", credit: "h15n.org", link: URL(string: "https://h15n.org"))
                Hairline()
                source("Quellcode", credit: "github.com/h15n-org/jord-dev",
                       link: URL(string: "https://github.com/h15n-org/jord-dev"))
                Hairline()
                source("Lizenz", credit: "GNU General Public License, Version 3 oder später",
                       link: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html"))
                Hairline()
                Text("Jord ist freie Software und wird ohne jede Gewährleistung bereitgestellt.")
                    .font(.footnote)
                    .foregroundStyle(Theme.quiet)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .card()
        }
    }

    @ViewBuilder
    private func source(_ title: LocalizedStringKey, credit: String, link: URL? = nil) -> some View {
        let row = HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.quiet)
                Text(credit)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 12)
            if link != nil {
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)

        if let link {
            Link(destination: link) { row }
        } else {
            row
        }
    }
}
