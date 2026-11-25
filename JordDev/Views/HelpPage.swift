// Part of Jord Dev. Copyright (C) 2026 Mikka Luster
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct HelpPage: View {
    private struct Topic: Identifiable {
        let id: Int
        let question: LocalizedStringKey
        let answer: [LocalizedStringKey]
    }

    private static let topics: [Topic] = [
        Topic(id: 0, question: "Wie checke ich in eine Fahrt ein?", answer: [
            "Wähle unter „Abfahrten“ den Bahnhof, an dem du einsteigst, und tippe auf „Abfahrten“. Tippe auf deinen Zug und dann auf den Halt, an dem du aussteigst.",
            "Jord zeigt die Fahrt mit allen Halten. Mit „Einchecken“ kommt sie in dein Reisetagebuch unter „Meine Reisen“.",
            "Eine Reise löschst du auf ihrer Seite über den Papierkorb oder in der Liste mit einem Wisch nach links.",
        ]),
        Topic(id: 1, question: "Wie arbeitet Jord mit Träwelling zusammen?", answer: [
            "Unter Profil → Träwelling tippst du auf „Mit Träwelling verbinden“ und meldest dich auf der Seite von Träwelling an. Jord sieht dein Passwort dabei nicht. Wer lieber einen Zugangstoken einfügt, erstellt ihn auf [traewelling.de](https://traewelling.de/settings/applications) unter „Deine Anwendungen“ mit „Token generieren“.",
            "Dort legst du auch fest, ob Jord jeden Check-in ohne Nachfrage an Träwelling sendet, jedes Mal fragt oder nichts sendet, und wer deine Check-ins sehen darf.",
            "Löschst du eine Reise, die auch bei Träwelling steht, fragt Jord, wo sie gelöscht werden soll.",
        ]),
        Topic(id: 2, question: "Wie kommen meine Reisen in den Kalender?", answer: [
            "Unter Profil → Kalender schaltest du das Eintragen ein und wählst den Kalender. Jord trägt jede Reise ein, in die du eincheckst, und hält den Termin aktuell.",
            "Der Kalender ändert nichts an deinem Reisetagebuch. Was du selbst am Termin änderst, überschreibt Jord, sobald sich die Reise ändert.",
        ]),
        Topic(id: 3, question: "Was zeigt Jord im WLAN des Zuges?", answer: [
            "Im WIFIonICE fragt Jord das Portal des Zuges nach Geschwindigkeit, nächstem Halt und Verspätung und zeigt sie unter „Live aus dem Zug“. Bist du in den Zug eingecheckt, siehst du auch, wie weit es noch bis zu deinem Ausstieg ist.",
            "Steigst du früher oder später aus als geplant, beendest du die Fahrt dort mit „Hier aussteigen“. Der Check-in bei Träwelling wird angepasst.",
        ]),
    ]

    @State private var open: Set<Int> = [0]

    var body: some View {
        ProfilePage(title: "Hilfe und FAQ") {
            ForEach(Self.topics) { topic in
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.snappy) { _ = open.remove(topic.id) ?? open.insert(topic.id).memberAfterInsert }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(topic.question)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .font(.footnote.weight(.semibold))
                                .rotationEffect(.degrees(open.contains(topic.id) ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)

                    if open.contains(topic.id) {
                        Hairline()
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(topic.answer.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                            }
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }
}
