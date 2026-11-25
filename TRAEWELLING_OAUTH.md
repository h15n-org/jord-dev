# Träwelling-Anmeldung über den Browser

Ohne weitere Einrichtung verbindest du die App über ein Token mit Träwelling (siehe [README](README.md)). Diese Datei beschreibt in groben Zügen, was nötig ist, damit stattdessen der Knopf „Mit Träwelling verbinden“ erscheint und die Anmeldung auf der Seite von Träwelling stattfindet.

Das ist mehr Aufwand als ein Token und lohnt sich nur, wenn du die App an andere weitergibst.

## Was du brauchst

- **Eine eigene Website mit https**, zum Beispiel `jorddev.example.org`. Träwelling akzeptiert als Rücksprungadresse nur https-Adressen, keine eigenen URL-Schemata.
- **Einen bezahlten Apple-Developer-Account.** Die Funktion „Associated Domains“, über die iOS die Rücksprungadresse an die App übergibt, steht mit einer kostenlosen Apple-ID nicht zur Verfügung.

## Einrichtung

1. **Anwendung bei Träwelling registrieren.** Unter [Einstellungen → Deine Anwendungen](https://traewelling.de/settings/applications) legst du eine Anwendung an:
   - als öffentlicher Client ohne Secret (die App verwendet PKCE),
   - mit der Rücksprungadresse `https://<dein-host>/oauth`.

   Träwelling zeigt dir danach die Client-ID der Anwendung.

2. **Die App auf deiner Website eintragen.** Lege auf dem Host die Datei `/.well-known/apple-app-site-association` an, ohne Dateiendung und ausgeliefert als `application/json`:

   ```json
   {
     "webcredentials": {
       "apps": ["<TEAM-ID>.<Bundle Identifier>"]
     }
   }
   ```

   Die Team-ID findest du in deinem Apple-Developer-Account, der Bundle Identifier ist der aus Xcode.

3. **`JordDev/Setup.swift` ausfüllen:**

   ```swift
   static let traewellingClientID = "<Client-ID>"
   static let traewellingCallbackHost = "<dein-host>"
   ```

4. **Den Host in `Config/JordDev.entitlements` eintragen.** Das Muster steht dort als Kommentar:

   ```xml
   <key>com.apple.developer.associated-domains</key>
   <array>
       <string>webcredentials:<dein-host></string>
   </array>
   ```

5. App neu bauen und installieren. Unter „Profil“ → „Träwelling“ steht jetzt „Mit Träwelling verbinden“; das Token-Feld bleibt als Alternative erhalten.

## Wie es funktioniert

- Die App öffnet die Anmeldeseite von Träwelling in einem Browserfenster des Systems. Das Passwort sieht sie dabei nicht.
- Sie fragt die Berechtigungen `read-statuses` und `write-statuses` an: Check-ins lesen sowie anlegen, ändern und löschen.
- Träwelling leitet nach der Anmeldung auf `https://<dein-host>/oauth` weiter. iOS fängt diese Adresse ab und gibt sie der App zurück; die Seite selbst muss es auf deinem Host nicht geben.
- Die Zugangstoken von Träwelling gelten eine Stunde, die Refresh-Token dreißig Tage. Die App erneuert sie selbst und speichert sie im Schlüsselbund. Nach dreißig Tagen ohne Nutzung musst du dich neu anmelden.
- „Verbindung trennen“ beendet die Anmeldung auch bei Träwelling.

## Wenn es nicht klappt

- **Der Knopf fehlt:** Eines der beiden Felder in `Setup.swift` ist leer.
- **Nach der Anmeldung kommt die App nicht zurück:** iOS hat die Datei auf deinem Host nicht gefunden oder die App steht nicht darin. Team-ID, Bundle Identifier und Host müssen an allen drei Stellen genau übereinstimmen. iOS lädt die Datei bei der Installation der App; nach einer Änderung hilft es, die App zu löschen und neu zu installieren.
- **Träwelling meldet einen Fehler bei der Anmeldung:** Die Rücksprungadresse der Anwendung bei Träwelling stimmt nicht genau mit `https://<dein-host>/oauth` überein.
