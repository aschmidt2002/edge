# Akku – Energie-Pacing für ME/CFS (Arbeitstitel)

Eine eigene App, getrennt von Edge+: eigener Name, eigene Bundle-ID
(`de.akkupacing.akku`, Platzhalter), eigenes `pubspec.yaml`, eigene iOS- und
Android-Projekte. Sie teilt keinen Code mit der Haupt-App und kann jederzeit in ein
eigenes Repository umziehen (siehe unten).

> Akku ist ein Tagebuch und eine Orientierungshilfe. Kein Medizinprodukt, keine
> Diagnose, kein Ersatz für ärztliche Beratung.

## Was die App heute kann

- **Energie-Akku** ganz oben auf der Startseite: Anteil des persönlichen
  Tagesrahmens, der noch übrig ist.
  - Startwert am Morgen aus Check-in, Ruhepuls und HRV im Vergleich zur eigenen
    14-Tage-Basis und einer "Schuld" aus überzogenen Vortagen (PEM kommt 12–72 h
    verzögert). Fehlende Daten werden ausgelassen, nie geschätzt.
  - Verbrauch live aus dem Puls gegen eine Pulsgrenze (Ruhepuls + 15, 55 % von
    220 − Alter, oder eigener Wert z. B. aus 2-Tages-CPET). Über der Grenze wird
    es deutlich teurer.
  - Geistige, emotionale und Kreislauf-Belastung (Duschen, Telefonat,
    Arzttermin …) per Hand eintragen, weil der Puls sie kaum sieht.
  - Ruhe gibt ein wenig zurück, höchstens 15 % pro Tag.
- **Rahmen, der mitwächst – aber vorsichtig:** +5 % nur nach 14 Tagen ohne Crash,
  in denen der Rahmen zu mindestens 70 % genutzt, nie überzogen wurde und die
  Symptome nicht schlechter wurden. Nach einem Crash sofort −10/15/20 % und 14
  Tage kein Wachstum. Jede Änderung steht mit Grund im Verlauf.
- **Vibration**: "Nah an der Grenze", "Akku niedrig", "Akku leer", "Über deiner
  Grenze" (30 s über der Pulsgrenze). Jede Warnung kommt einmal pro Episode,
  Ruhezeit nachts (nur die Pulsgrenze kommt durch). Heute über das Handy und eine
  gekoppelte Apple Watch; Vibration am WHOOP selbst ist als Schnittstelle
  (`BandBuzzer`) vorbereitet.
- **Täglicher Check-in**: ein Tipp reicht (Wie geht es dir, 0–4, Crash ja/nein);
  optional Erschöpfung, Brain Fog, Schmerz, Schlaf, Kreislauf, Periode, Infekt,
  Notiz.
- **Crash-Rückblick**: Zu jedem gemeldeten Crash zeigt der Verlauf, was die 1–3
  Tage davor gekostet haben, größte Posten zuerst. Kandidaten, keine Ursache.
- **Medikamente & Nahrungsergänzung** mit Uhrzeiten und "Jetzt genommen".
  Pulssenkende Mittel (Betablocker, Ivabradin) werden markiert: dann sind die
  Faustregeln für die Pulsgrenze unzuverlässig und die App sagt das.
- **Ideen je nach Akku und Schweregrad** (NICE-Einteilung leicht bis sehr
  schwer): bei leerem Akku oder im Crash nur Ruhe; sonst z. B. Hörbuch im Liegen,
  Häkeln mit Pausen, kurzer Spaziergang unter der Grenze. Jede Idee lässt sich
  ausblenden.
- **Datenquellen**: jeder Pulssensor mit Standard-Bluetooth-Herzfrequenz (WHOOP
  mit "Herzfrequenz übertragen", Polar Verity Sense/H10, Brustgurte) und Apple
  Health / Health Connect (Ruhepuls, HRV, Schlaf, Schritte; nur lesen).
- Alles bleibt auf dem Gerät (eine JSON-Datei), Export als JSON.
- Ruhiges, dunkles Design mit großen Tasten.

## WHOOP und iPhone

| Weg | Was geht | Was nicht | Für wen |
|---|---|---|---|
| **Herzfrequenz übertragen** (Standard-Bluetooth, in der WHOOP-App einschalten) | Live-Puls auf iPhone und Android, auch im Hintergrund (iOS-Modus `bluetooth-central`) | kein HRV über Nacht, keine Vibration am Band | jede WHOOP mit Mitgliedschaft – **in dieser App eingebaut** |
| **Apple Health / Health Connect** (die WHOOP-App schreibt hinein) | Ruhepuls, HRV, Schlaf für den Morgenwert | kein Live-Puls, Verzögerung bis zum Sync | **eingebaut** |
| **WHOOP Developer API** (OAuth, Cloud) | Recovery, HRV, Schlaf, Strain, Workouts | kein Live-Puls, keine Vibration, braucht Server/Registrierung | später, optional |
| **Direkte Verbindung** (OpenStrap-Protokoll, wie in Edge+) | alles inkl. Vibration am Band, ohne Mitgliedschaft | neue WHOOP 5.0/MG-Firmware 50.43.x kann Daten sperren; nur ein Bluetooth-Partner gleichzeitig; AGPL | Phase 2, siehe unten |

Wichtig vor dem Kauf: Eine **neue** WHOOP 5.0/MG muss in der offiziellen App
aktiviert werden und bekommt dabei aktuelle Firmware. Laut den Berichten in der
Edge-README gibt eine Band mit Firmware 50.43.x ohne von WHOOP signiertes
Mitglieds-Token keine Daten mehr an fremde Apps heraus. Für eine neue Band ist
daher "WHOOP-Mitgliedschaft + Herzfrequenz übertragen + Apple Health" der sichere
Weg. Günstige Alternative ohne Abo: Polar Verity Sense (Oberarm, Standard-HR),
die auch Visible verwendet hat.

## Phase 2 (vorbereitet, nicht gebaut)

- WHOOP direkt über das Protokoll-Paket (`OpenStrap/protocol`, per SHA gepinnt):
  Band vibrieren lassen (`BandBuzzer`), HRV/Ruhepuls über Nacht ohne Umweg.
  Rechtlich: Edge ist AGPL-3.0 und "OpenStrap" ist eine Marke. Wer Code
  übernimmt, muss die App ebenfalls unter AGPL veröffentlichen und darf den
  Namen nicht verwenden (siehe `TRADEMARKS.md`).
- Orthostatischer Test (NASA Lean Test, 10 min) mit Pulsverlauf.
- Morgen-HRV-Messung 1 Minute im Liegen, falls kein Nachtwert vorliegt.
- Bericht als PDF für Arzttermine, Begleitperson-Modus, englische Übersetzung,
  Homescreen-Widget mit dem Akku.

## Bauen

```bash
cd pacing
flutter pub get
flutter test
flutter run            # Android oder iOS
```

iOS: In Xcode das Team setzen und unter *Signing & Capabilities* **HealthKit**
aktivieren (das Entitlement liegt schon in `ios/Runner/Runner.entitlements`).
Android: Health Connect muss installiert sein (ab Android 14 eingebaut),
`minSdk` ist 26.

Vor dem ersten Store-Upload festlegen: endgültiger Name, Bundle-ID / applicationId
(später nicht mehr änderbar), Release-Signatur, Datenschutzerklärung.

## Eigenes Repository

Der Ordner hängt an nichts außerhalb von sich selbst. Umzug mit Verlauf:

```bash
git subtree split --prefix=pacing -b akku-only
# neues leeres Repo anlegen, dann:
git push git@github.com:<du>/akku.git akku-only:main
```
