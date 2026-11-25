// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later

/// What whoever builds the app fills in for themself. Nothing here is a secret.
enum Setup {
    /// How the timetable's operators can reach you, sent with every request to Transitous in
    /// the User-Agent. Their usage policy asks every client for one: put in your own address
    /// or the page of your project.
    static let contact = "your-contact@example.com"

    /// The ID of your application on Träwelling, for signing in in the browser. It is public;
    /// there is no secret. Empty, the sign-in button is hidden and a pasted token is the way in.
    static let traewellingClientID = ""

    /// The host of the https address Träwelling sends the browser back to after the sign-in,
    /// as registered with your application there. It has to be a site of yours that names this
    /// app in its `apple-app-site-association`, and it goes into `Config/JordDev.entitlements`
    /// as `webcredentials:<host>` too.
    static let traewellingCallbackHost = ""
}
