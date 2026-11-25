// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Profile page for Träwelling: connect by browser sign-in or pasted token, disconnect,
// and choose how check-ins are sent.

import AuthenticationServices
import SwiftUI

struct TraewellingPage: View {
    private enum Phase: Equatable {
        case idle, working
        case failed(String)
    }

    @AppStorage("traewellingUsername") private var username = ""
    @AppStorage(TraewellingSettings.modeKey) private var mode = TraewellingSettings.Mode.ask
    @AppStorage(TraewellingSettings.visibilityKey) private var visibility = TraewellingSettings.defaultVisibility
    @State private var token = Keychain.read(TraewellingClient.tokenAccount) ?? ""
    @State private var input = ""
    @State private var phase = Phase.idle
    @State private var showsTokenField = false
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    private var isConnected: Bool { !token.isEmpty && !username.isEmpty }

    var body: some View {
        ProfilePage(title: "Träwelling") {
            if isConnected {
                account
                checkInSettings
            } else {
                connect
            }
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 10) {
            if TraewellingOAuth.isAvailable {
                Text("Melde dich bei Träwelling an und erlaube Jord, deine Check-ins zu lesen und zu schreiben.")
                    .font(.footnote)
                    .foregroundStyle(Theme.quiet)
                Button("Mit Träwelling verbinden", systemImage: "link") {
                    Task { await signIn() }
                }
                .buttonStyle(InkButtonStyle())
                .disabled(phase == .working)
                Button(showsTokenField ? "Zugangstoken ausblenden" : "Stattdessen mit Zugangstoken verbinden") {
                    showsTokenField.toggle()
                }
                .font(.footnote)
                .tint(Theme.ink)
            }
            if !TraewellingOAuth.isAvailable || showsTokenField {
                tokenFields
            }
            if let message {
                note(message)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var tokenFields: some View {
        SecureField("Zugangstoken", text: $input)
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        Text("Erstelle den Token bei Träwelling unter „Deine Anwendungen“ mit „Token generieren“ und füge ihn hier ein. Jord speichert ihn im Schlüsselbund dieses Geräts.")
            .font(.footnote)
            .foregroundStyle(Theme.quiet)
        Link(destination: TraewellingSettings.tokenPage) {
            Label("Token bei Träwelling erstellen", systemImage: "arrow.up.right")
        }
        .buttonStyle(OutlineButtonStyle())
        Button("Verbinden", systemImage: "link") {
            Task { await connectAccount() }
        }
        .buttonStyle(InkButtonStyle())
        .disabled(phase == .working)
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Verbunden als")
                    .font(.caption)
                    .foregroundStyle(Theme.quiet)
                Text(verbatim: "@\(username)")
                    .fontWeight(.semibold)
            }
            Button("Verbindung trennen", systemImage: "xmark.circle") {
                Task { await disconnect() }
            }
            .buttonStyle(OutlineButtonStyle())
            .disabled(phase == .working)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var checkInSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingRow("Beim Einchecken") {
                Picker("Beim Einchecken", selection: $mode) {
                    ForEach(TraewellingSettings.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
            if mode != .never {
                Hairline()
                settingRow("Sichtbarkeit") {
                    Picker("Sichtbarkeit", selection: $visibility) {
                        ForEach(TraewellingSettings.visibilities, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                }
            }
            Hairline()
            Text(hint)
                .font(.footnote)
                .foregroundStyle(Theme.quiet)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .card()
    }

    private func settingRow(_ title: LocalizedStringKey, @ViewBuilder picker: () -> some View) -> some View {
        let picker = picker().labelsHidden().tint(Theme.ink).fixedSize()
        return ViewThatFits(in: .horizontal) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                picker
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.quiet)
                picker
                    .padding(.leading, -12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func note(_ message: (text: String, isError: Bool)) -> some View {
        Text(message.text)
            .font(.footnote)
            .foregroundStyle(message.isError ? Pastel.delayed.ink : Theme.quiet)
    }

    private var hint: String {
        switch mode {
        case .ask: String(localized: "Jord fragt bei jedem Check-in, ob die Fahrt auch zu Träwelling soll. Die Sichtbarkeit ist dort vorausgewählt.")
        case .automatic: String(localized: "Jeder Check-in geht ohne Nachfrage mit dieser Sichtbarkeit zu Träwelling.")
        case .never: String(localized: "Check-ins bleiben in Jord. Einzelne Reisen kannst du später senden.")
        }
    }

    private var message: (text: String, isError: Bool)? {
        switch phase {
        case .idle, .working: nil
        case .failed(let text): (text, true)
        }
    }

    private func signIn() async {
        let attempt = TraewellingOAuth.attempt()
        phase = .working
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: attempt.url,
                callback: .https(host: TraewellingOAuth.callbackHost, path: TraewellingOAuth.callbackPath),
                additionalHeaderFields: [:])
            try await TraewellingOAuth.finish(attempt, callback: callback)
            let user = try await TraewellingClient(token: "").user()
            token = Keychain.read(TraewellingClient.tokenAccount) ?? ""
            username = user.username
            phase = .idle
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            phase = .idle
        } catch {
            TraewellingOAuth.forget()
            Keychain.write(nil, account: TraewellingClient.tokenAccount)
            let text = switch error {
            case TraewellingError.unauthorized:
                String(localized: "Die Anmeldung bei Träwelling ist fehlgeschlagen. Versuche es noch einmal.")
            default: Self.describe(error)
            }
            phase = .failed(text)
        }
    }

    private func disconnect() async {
        phase = .working
        if TraewellingOAuth.isSignedIn {
            try? await TraewellingClient(token: token).signOut()
        }
        TraewellingOAuth.forget()
        Keychain.write(nil, account: TraewellingClient.tokenAccount)
        token = ""
        username = ""
        phase = .idle
    }

    private func connectAccount() async {
        let candidate = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            phase = .failed(String(localized: "Füge zuerst deinen Zugangstoken ein."))
            return
        }
        phase = .working
        do {
            let user = try await TraewellingClient(token: candidate).user()
            TraewellingOAuth.forget()
            Keychain.write(candidate, account: TraewellingClient.tokenAccount)
            token = candidate
            username = user.username
            input = ""
            phase = .idle
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case TraewellingError.unauthorized:
            String(localized: "Träwelling hat den Token abgelehnt. Prüfe, ob er vollständig und noch gültig ist.")
        case TraewellingError.declined:
            String(localized: "Du hast Jord den Zugriff bei Träwelling nicht erlaubt.")
        case TraewellingError.http(let status):
            String(localized: "Träwelling hat mit Fehler \(status) geantwortet. Versuche es später noch einmal.")
        case is DecodingError:
            String(localized: "Die Antwort von Träwelling hatte ein unerwartetes Format.")
        default:
            String(localized: "Träwelling ist nicht erreichbar. Prüfe deine Internetverbindung.")
        }
    }
}
