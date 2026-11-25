# Jord Dev

Jord ist eine kleine iPhone-App, um sich in Zügen in Deutschland einzuchecken. Wähle den Bahnhof aus, an dem du dich befindest, sieh dir die Abfahrten an, tippe auf deinen Zug sowie auf die Haltestelle, an der du aussteigen möchtest – und schon bist du eingecheckt.

Jord ist Open Source, verfügbar auf GitHub, und steht unter der GNU General Public License (GPL), Version 3 oder – nach deiner Wahl – jeder späteren Version. Das bedeutet, dass du mit dem Code mehr oder weniger machen darfst, was du magst, solange du Änderungen, wenn du welche vornimmst, auch wieder verfügbar machst. Die ganze Lizenz liegt in diesem Ordner in der Datei `LICENSE`.

Copyright © 2026 Mikka Luster <mikka@h15n.org>. Jord wird ohne jede Gewährleistung bereitgestellt; die Einzelheiten stehen in der Lizenz.

- **Abfahrten** für jeden Bahnhof, filterbar nach Fern- oder Regionalverkehr, inklusive Verspätungen und Gleisangaben. Die Fahrplandaten stammen von [Transitous](https://transitous.org) und [seinen Datenquellen](https://transitous.org/sources/), darunter © [OpenStreetMap](https://www.openstreetmap.org/copyright)-Mitwirkende.
- **Ein Fahrtenbuch** mit einer Übersicht deiner eingecheckten Fahrten.
- **Träwelling:** Übermittle jeden Check-in an dein [Träwelling](https://traewelling.de)-Konto – wahlweise bei jedem Mal, immer oder nie.
- **Kalender:** Lass jede Fahrt automatisch in einen Apple-Kalender deiner Wahl eintragen und aktuell halten.
- **WIFIonICE:** Im WLAN eines ICE zeigt die App die aktuelle Geschwindigkeit, den nächsten Halt sowie die Entfernung bis zu deinem Zielbahnhof an. Zudem kannst du die Fahrt direkt im Zug beenden.

Die App ist komplett auf Deutsch. Es gibt keinen Server und kein Benutzerkonto: Alle Daten verbleiben auf deinem Gerät – abgesehen von den Anfragen an die oben genannten Dienste.

## Voraussetzungen

- Ein Mac mit Xcode 27
- Ein iPhone mit iOS 27 (oder der iOS-27-Simulator)
- Eine Apple-ID. Ein kostenloser Account reicht aus, um die App auf deinem eigenen iPhone zu installieren; allerdings lassen sich auf diese Weise signierte Apps nach sieben Tagen nicht mehr öffnen und müssen dann erneut installiert werden.

Es gibt keine Version im App Store oder über TestFlight. Du musst die App selbst kompilieren.

## Installation

1. Klone das Repository und öffne `JordDev.xcodeproj` in Xcode.
2. Wähle das Target `JordDev` aus und gehe zu **Signing & Capabilities**:
   - Wähle dein eigenes „Team“ aus.
   - Ersetze den Platzhalter `com.example.jorddev` im Feld „Bundle Identifier“ durch einen eigenen, zum Beispiel `de.deinname.jorddev`.
3. Trage in der Datei `JordDev/Setup.swift` bei `contact` deine eigene Kontaktadresse ein. Sie wird im User-Agent an Transitous gesendet; Transitous verlangt von jedem Client eine solche Angabe. Die beiden Träwelling-Felder in dieser Datei können leer bleiben: Träwelling funktioniert dann mit einem Token (siehe unten).
4. Wähle dein iPhone oder einen Simulator aus und klicke auf „Run“.

Sobald das iPhone verbunden ist und die Signierung in Xcode eingerichtet wurde, kannst du die App auch über das Terminal erstellen und installieren:

    make debug BUNDLE_ID=de.deinname.jorddev

`make ios` baut stattdessen die Release-Version. `BUNDLE_ID` muss dem Bundle Identifier aus Schritt 2 entsprechen, sonst wird die App installiert, aber nicht gestartet.

## Verbindung mit Träwelling

So, wie die App aus diesem Repository kommt, verbindest du sie über ein Token mit Träwelling:

1. Öffne auf Träwelling den Bereich [Einstellungen → Deine Anwendungen](https://traewelling.de/settings/applications) und generiere ein Token.
2. Gehe in der App auf „Profil“ → „Träwelling“ und füge das Token dort ein.

Das Token wird im Schlüsselbund (Keychain) des iPhones gespeichert.

Die Anmeldung über den Browser („Mit Träwelling verbinden“) erscheint erst, wenn du eine eigene Anwendung bei Träwelling registriert und in `JordDev/Setup.swift` eingetragen hast. Wie das geht, steht in [TRAEWELLING_OAUTH.md](TRAEWELLING_OAUTH.md).

## Berechtigungen

- **Standort:** Wird nur verwendet, wenn du auf „Bahnhöfe in der Nähe“ tippst. Die Positionsdaten werden auf etwa 100 m gerundet, bevor sie an Transitous übertragen werden.
- **Kalender:** Wird nur verwendet, wenn du unter „Profil“ → „Kalender“ die entsprechende Option aktivierst. Die App benötigt vollen Zugriff, da sie die von ihr erstellten Kalendereinträge auch wieder ändern oder löschen kann. Andere Kalendereinträge werden nicht gelesen.

## Gut zu wissen

- Bitte gehe schonend mit den Diensten Transitous und Träwelling um – beide werden von Freiwilligen betrieben. Wenn du Transitous verwendest, **musst** du deinen Quellcode nach einer kurzen Testphase unter einer Open-Source-Lizenz veröffentlichen, und dein Projekt darf nicht kommerziell sein. Die vollständigen Bedingungen stehen in der [Nutzungsrichtlinie von Transitous](https://transitous.org/api/). Alternativ kannst du deinen eigenen MOTIS-Server betreiben.
- Die Abfahrtstafel ist nach der tatsächlichen Abfahrtszeit sortiert. Ein verspäteter Zug kann daher unter einem späteren Zug erscheinen, der pünktlich ist.
- Manche Bahnhöfe werden nur mit ihrem allgemeinen Namen angezeigt; so erscheint beispielsweise „Stuttgart Hbf“ in der Halteliste eines Zuges lediglich als „Hauptbahnhof“.
- Änderungen, die du an einem von der App erstellten Kalendereintrag vornimmst, werden überschrieben, sobald sich die Fahrtinformationen ändern.
- Die Live-Karte funktioniert in ICE-Zügen über das Portal „WIFIonICE“ und gilt ausschließlich für Fahrten in Fernverkehrszügen.
- Es gibt keine automatisierten Tests.
