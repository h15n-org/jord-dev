// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Browser sign-in to Träwelling (OAuth with PKCE, no client secret) and the session that
// refreshes its tokens. Only active when Setup.swift is properly configured for it.

import CryptoKit
import Foundation

enum TraewellingOAuth {
    static let clientID = Setup.traewellingClientID

    static let callbackHost = Setup.traewellingCallbackHost
    static let callbackPath = "/oauth"
    static var redirectURI: String { "https://\(callbackHost)\(callbackPath)" }

    static let scopes = "read-statuses write-statuses"

    static let refreshAccount = "traewelling-refresh-token"
    static let expiryKey = "traewellingTokenExpiry"

    static var isAvailable: Bool { !clientID.isEmpty && !callbackHost.isEmpty }

    static var isSignedIn: Bool { !(Keychain.read(refreshAccount) ?? "").isEmpty }

    struct Attempt: Sendable {
        let url: URL
        let verifier: String
        let state: String
    }

    static func attempt() -> Attempt {
        let verifier = randomText()
        let state = randomText()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var components = URLComponents(string: "https://traewelling.de/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return Attempt(url: components.url!, verifier: verifier, state: state)
    }

    static func finish(_ attempt: Attempt, callback: URL) async throws {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == attempt.state, let code = value("code") else {
            throw value("error") == "access_denied" ? TraewellingError.declined : TraewellingError.unauthorized
        }
        try await requestTokens([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": attempt.verifier,
            "code": code,
        ])
    }

    fileprivate static func refresh(with refreshToken: String) async throws -> String {
        try await requestTokens([
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ])
    }

    static func forget() {
        Keychain.write(nil, account: refreshAccount)
        UserDefaults.standard.removeObject(forKey: expiryKey)
    }

    @discardableResult
    private static func requestTokens(_ form: [String: String]) async throws -> String {
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: "https://traewelling.de/oauth/token")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = Data((body.percentEncodedQuery ?? "").replacing("+", with: "%2B").utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(TraewellingClient.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        // Träwelling answers a spent, expired or revoked code or refresh token with 400 or 401.
        case 400, 401: throw TraewellingError.unauthorized
        default: throw TraewellingError.http(status)
        }
        let tokens = try JSONDecoder().decode(TokenDTO.self, from: data)
        Keychain.write(tokens.access_token, account: TraewellingClient.tokenAccount)
        Keychain.write(tokens.refresh_token, account: refreshAccount)
        UserDefaults.standard.set(
            Date.now.addingTimeInterval(TimeInterval(tokens.expires_in)), forKey: expiryKey)
        return tokens.access_token
    }

    private static func randomText() -> String {
        Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64URL
    }

    private struct TokenDTO: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
    }
}

actor TraewellingSession {
    static let shared = TraewellingSession()

    private var refreshing: Task<String, Error>?

    func accessToken() async throws -> String? {
        if let refreshing { return try await refreshing.value }
        guard let refreshToken = Keychain.read(TraewellingOAuth.refreshAccount), !refreshToken.isEmpty else {
            return nil
        }
        let expiry = UserDefaults.standard.object(forKey: TraewellingOAuth.expiryKey) as? Date ?? .distantPast
        if expiry.timeIntervalSinceNow > 60, let token = Keychain.read(TraewellingClient.tokenAccount) {
            return token
        }
        let task = Task { try await TraewellingOAuth.refresh(with: refreshToken) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
    }
}
