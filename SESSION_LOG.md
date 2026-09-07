# Sitzungsprotokoll — Sceau Stabilitäts-/Bugfix-Durchgang

Datum: 2026-09-04/05. Nicht Teil des Codebase-Repos im engeren Sinn (nicht
committet) — dient als Gedächtnisstütze über diese Sitzung hinweg.

## Kontext

Auftrag des Nutzers, chronologisch:
1. `missing.md` (privates Wunsch-Backlog) umsetzen, soweit sinnvoll/machbar.
2. Danach: Stabilitäts-/Bugfix-/Optimierungs-/UX-Durchgang, bis Budget
   (Claude + Codex/Gemini) erschöpft ist. Priorität: **Stabiler > Optimiert**.
3. Delegation an Codex bleibt Standardweg für Boilerplate (siehe
   `agent-rules.md` Abschnitt 7) — Gemini-MCP war in dieser Sitzung nie
   verfügbar, daher durchgehend Codex.
4. Blanko-Erlaubnis für normale Entwicklungsarbeit in diesem Projektordner
   ohne Rückfrage — **ausgenommen**: destruktive, breite Löschoperationen
   ausserhalb des Projekts, und (neu in dieser Sitzung) keine automatisierte
   UI-Steuerung der laufenden App per Accessibility/osascript mehr.

## Was in dieser Sitzung erledigt wurde (grob chronologisch)

### 1. missing.md-Umsetzung (vor dem hier protokollierten Teil)
- Neue Grundform **Squircle** (`ShapeSpec.squircle`, `ShapeGeometry.squirclePath`,
  Werkzeug + Menüeintrag + Inspector-Anbindung).
- **Freies Verzerren** (Distort-Werkzeug): `FreeDistortion`/`QuadCorners`
  (bilineare Interpolation), `NodeTransform.distorted`, CanvasView-Interaktion
  (`Interaction.distorting`), Menüeintrag „Verzerren" (⌘⇧K).
- **Proportionales Skalieren** (Option-Taste beim Ziehen eines Eckgriffs):
  `ProportionalResize.lockedRect`.
- Mehrere jetzt schon vorhandene Features aus `missing.md` waren bereits
  umgesetzt oder wurden als aktuell nicht sinnvoll/zu aufwendig zurückgestellt
  (siehe „Nicht umgesetzt" unten).

### 2. Erste Codex-Audit-Runde + Fixes
- Absturzrisiken behoben: Integer-Overflow bei `sides`/`points` in
  Polygon/Stern (`maxPolygonOrStarCount = 1000`), NaN/Infinity beim Decodieren
  von Farben/Gradient-Stops (`RGBAColor`/`GradientStop` mit expliziten,
  clamping `init(from:)`), unsichere Pixel-Längen beim Export
  (`RasterExporter.safePixelLength`, `maxPixelLength = 16384`).
- Commit: `c81712e` „Absturzrisiken behoben..."

### 3. Zweite Codex-Audit-Runde + Fixes
Jede gemeldete Stelle wurde **im echten Code verifiziert** — die Audit-Berichte
enthielten mehrfach falsche Dateipfade (z. B. `Views/CanvasView.swift` statt
tatsächlich `Canvas/CanvasView.swift`); zwei gemeldete Funde wurden nach
Prüfung als False Positive / bereits abgesichert verworfen (Flattener-
Rekursionstiefe bei Gruppen, Grid-Linien-Rendering in CanvasView).

Tatsächlich behobene, verifizierte Funde:
- **⌘Y (Redo) reagierte nicht**: verstecktes `NSMenuItem` ohne
  `allowsKeyEquivalentWhenHidden = true` ignoriert sein Tastaturkürzel.
- **Cursor-Rect-Grössenfehler** in `CanvasView.resetCursorRects()`: Rect war
  doppelt so gross wie die tatsächliche Trefferzone der Griffe
  (`handleScreenSize` als Halbbreite verwendet statt `handleScreenSize / 2`).
- **PathfinderCommands: globale statt Dokument-lokale Sperre** + **Race
  Condition**: eine zu Ende laufende boolesche Verknüpfung konnte auf ein
  inzwischen durch den Nutzer verändertes Dokument angewendet werden.
  Fix: pro-Dokument `Set<ObjectIdentifier>` + `Document == documentAtStart`-
  Staleness-Check vor dem Anwenden des Ergebnisses.
- **Gruppen verloren beim Verzerren ihren Stil** (Distort flachte eine
  Gruppe komplett zu einem Pfad ab, `NodeGeometry.path(for:)` verwirft dabei
  pro-Kind-Stile). Fix: `NodeTransform.distorted` rekursiert jetzt pro Kind
  für **unrotierte** Gruppen; rotierte Gruppen bleiben bewusst wie bisher
  (dokumentierte, akzeptierte Einschränkung, analog zu einer bereits
  bestehenden, bewusst unangetasteten Rotations-Einschränkung in
  `NodeTransform.resized`).
- **Ausschneiden/Kopieren von Objekten innerhalb einer Gruppe verlor Daten
  unwiderruflich** (höchste Schwere dieser Sitzung!): `ClipboardCommands.copy`/
  `.duplicate` nutzten die flache `document.nodes` (nur oberste Ebene),
  während das zugrunde liegende `remove(ids:)` rekursiv ist — ein Ausschneiden
  aus einer Gruppe heraus entfernte das Objekt aus dem Dokument, **ohne** dass
  es je auf der Zwischenablage landete. Fix: `copy`/`duplicate` nutzen jetzt
  die rekursive `document.nodes(with:)`; `cut` bricht ab, falls `copy` nicht
  wirklich etwas auf die Zwischenablage gelegt hat.
- **`Dictionary(uniqueKeysWithValues:)`-Absturz** bei doppelten Knoten-UUIDs
  (erreichbar über eine von Hand beschädigte Dokumentdatei) in
  `LayerListView.move(source:to:)` — Fix via `uniquingKeysWith`.
- Commit: `8338901` „Weitere Stabilitäts-/Korrektheitsfixes aus zweiter
  Audit-Runde"

### 4. Wichtiger, in dieser Sitzung entdeckter Prozessfehler
`swift build`/`swift test` deckt **nur** das SPM-Paket `SceauCore` ab, **nicht**
das eigentliche App-Target `App/Sceau` (Xcode-Projekt, generiert via
`xcodegen generate` aus `project.yml`). Eine Änderung, die nur SceauCore-Tests
grün hatte, brach den App-Build (fehlender `.squircle`-Case in
`CanvasView.cursor(for:)`). Ab sofort **vor jedem Push zusätzlich**:

```bash
xcodegen generate
xcodebuild -project Sceau.xcodeproj -scheme Sceau -configuration Debug build
```

Als Projekt-Memory dauerhaft gespeichert
(`~/.claude/projects/.../memory/xcodebuild-vs-swift-build.md`).

### 5. Menüvalidierung (dritter Fund aus Audit-Runde 2: „Menüvalidierung
   aktiviert praktisch alle Befehle unabhängig vom Kontext")
`DocumentWindowController.validateUserInterfaceItem(_:)` deaktiviert jetzt:
- **Gruppieren** ohne ≥ 2 ausgewählte Objekte,
- **Gruppierung aufheben** ohne ausgewählte Gruppe,
- **Boolesche Operationen** ohne ≥ 2 ausgewählte Objekte oder während eine
  Verknüpfung für dieses Dokument bereits läuft (`PathfinderCommands.isBusy`),
- **Text in Pfade umwandeln** ohne ausgewähltes Textobjekt.
- Commit: `0afcd3e` „Menüvalidierung: Befehle nur aktiv, wenn sie etwas
  bewirken"

### 6. Änderungszähler-Bug (Undo/Redo vs. Dirty-Tracking) — selbst gefunden,
   nicht aus einer Codex-Audit-Runde
`SceauDocument.connectStore()` meldete **jede** Modelländerung unterschiedslos
als `.changeDone` an `updateChangeCount(_:)` — auch beim Widerrufen und
Wiederholen. Dadurch zählte der interne Änderungszähler beim Widerrufen weiter
nach **oben** statt nach unten: Ein Dokument blieb nach einem Undo, das es
exakt auf den zuletzt gesicherten Stand zurückbrachte, fälschlich als
„geändert" markiert (Titelleisten-Punkt, „Schliessen ohne Speichern?"-Dialog
zu Unrecht). Fix nutzt `UndoManager.isUndoing`/`isRedoing`, die im Moment des
`didChange`-Aufrufs zuverlässig gesetzt sind, um zwischen `.changeDone`,
`.changeUndone` und `.changeRedone` zu unterscheiden.

Test-first (Kern-Regel des Projekts): Ein neuer Test in
`DocumentStoreTests.swift` verifiziert an einem echten `UndoManager`, dass
`didChange` bei Ändern/Widerrufen/Wiederholen mit dem jeweils passenden
`isUndoing`/`isRedoing`-Zustand feuert — das ist die reine SceauCore-testbare
Grundlage; der eigentliche App-seitige Fix in `SceauDocument.swift` liegt
ausserhalb von `swift test` und wurde zusätzlich per `xcodebuild` verifiziert.
- Commit: `0c410f9` „Änderungszähler unterscheidet Widerrufen/Wiederholen von
  echten Änderungen"

## Stand der Testabdeckung
- SceauCoreTests: **217/217 grün** (28 Suiten).
- App-Target (`xcodebuild ... build`): **BUILD SUCCEEDED**, nach jedem der
  obigen Commits erneut verifiziert.

## Bewusst NICHT umgesetzt / zurückgestellt (explizit begründet, kein
   stillschweigendes Weglassen)
- Rotierte Gruppen beim Verzerren (`NodeTransform.distorted`) — siehe oben,
  analoge Einschränkung existiert bereits bei `resized`.
- PNG-Export-Seitenverhältnis bei extremen Ziel-Pixelgrössen: `pngData`
  streckt bewusst auf die angeforderte Zielgrösse, das ist Aufrufer-
  Verantwortung, kein Bug in der Exportfunktion selbst — nach Prüfung nicht
  weiterverfolgt.
- Kein dediziertes Xcode-Unit-Test-Target für den App-Layer (`ClipboardCommands`
  etc. sind nur über Code-Lesen/manuelles Nachvollziehen geprüft, nicht durch
  automatisierte App-Target-Tests) — Aufwand für diese Sitzung als zu hoch
  eingeschätzt, wäre ein separates, grösseres Vorhaben.
- Inspector-Zahlenfelder wurden überprüft: die meisten haben bereits
  sinnvolle `max(...)`/`min(...)`-Clamps; die Deckkraft läuft über einen
  SwiftUI-`Slider` mit `in: 0...1`, der Werte technisch gar nicht ausserhalb
  dieses Bereichs zulässt — kein Fix nötig.
- Aus `missing.md` weiterhin unumgesetzt (auf expliziten Wunsch des Nutzers
  zugunsten des Stabilitäts-Durchgangs zurückgestellt): Texturen, Effekte,
  Hintergrund-Entfernung, automatisch einklappende Icon-Seitenleiste
  (Pixelmator-artig), weitere Formen-Vorlagen über Squircle hinaus,
  Mehrpinsel-Freihandwerkzeug.
- Standing-Constraint aus dieser Sitzung: keine weitere automatisierte
  UI-Steuerung der laufenden App per Accessibility/osascript — auf
  ausdrücklichen Wunsch des Nutzers, nach Ablehnung eines entsprechenden
  Tool-Aufrufs. Verifikation lief seitdem ausschliesslich über
  `swift test`/`xcodebuild`.

## Offene Frage aus früherer Session (nicht in dieser Sitzung erneut
   aufgegriffen)
Ob der Remote-Branch `feature/mvp-umsetzung` gelöscht werden soll, ist
weiterhin unbeantwortet.

## Sitzung: missing.md vollständig umgesetzt + Problems.md behoben

Auf ausdrücklichen Wunsch ("Nein setz alles aus missing.md um") wurde die
vollständige Wunschliste umgesetzt statt eines reinen Stabilitäts-Durchgangs.
Zwei Punkte (Texturen, Freihand-Mehrpinsel) standen im Widerspruch zum
dokumentierten Nicht-Ziel in `docs/entwicklungsplan.md` Abschnitt 6 — nach
Rückfrage vom Nutzer bestätigt: "Trotzdem umsetzen, Plan aktualisieren".
Der Plan wurde entsprechend revidiert (Abschnitt 5.2b/5.4, Abschnitt 6 mit
`> Revidiert:`-Hinweis).

### Umgesetzt
- **Vier neue Formvorlagen**: Herz, Pfeil, Sprechblase, Kreuz
  (`ShapeGeometry.swift`, `ShapeSpec.swift`, ins bestehende Formen-Menü
  eingehängt wie zuvor Squircle). Commit `fb4d752`.
- **Texturen**: Musterfüllung mit einer Bildkachel (`Paint.pattern`,
  Kachelgrösse + Rotation, Sicherheits-Deckel gegen zu viele Kacheln bei
  winzigem `tileSize`). Commit `299000e`.
- **Effekte**: Schlagschatten (`Style.shadow`), inkl. der Vorzeichen-Falle
  bei `CGContext.setShadow` (Offset ist im unveränderten Default-User-Space
  gemeint, nicht in der aktuellen — bereits gespiegelten — CTM; beim Export
  muss `dy` deshalb negiert werden, im Live-Canvas über `CALayer.shadowOffset`
  nicht). Commit `5dbbb82`.
- **Freihand-Werkzeug mit drei Stiften** (Filzstift/Pinsel/Eimer) —
  Douglas-Peucker-Vereinfachung (iterativ, nach Stack-Overflow-Absturz bei
  20 000 Punkten von rekursiv auf iterativ mit explizitem Stack umgebaut)
  + Catmull-Rom-zu-Bézier. In den Zeichenstift-Knopf als Menü eingehängt
  (genau sieben Werkzeugleisten-Elemente bleiben gewahrt). Commit `c89ab84`.
  **Der Eimer war hier zunächst nur eine 24pt-dicke Freihand-Linie, kein
  echtes Füllwerkzeug** — siehe Problems.md-Fix unten.
- **Bild einfügen**: Statt eigener Freistellung (Vision-Framework) nutzt
  Sceau bewusst das bereits vom Nutzer freigestellte PNG — "Motiv kopieren"
  in Vorschau/Fotos/Finder, dann `Datei > Bild einfügen …`. Neuer `.image`-
  Content-Fall im Dokumentmodell, generisch überall eingehängt
  (Rendering, Export, Treffertest, Transformationen). Dabei proaktiv einen
  stillen Datenverlust in `NodeTransform.distorted` verhindert: Bilder
  dürfen beim Verzerren nicht zu einem leeren Pfad kollabieren, sondern
  behalten ihre Pixel und bekommen nur einen neuen Rahmen (Hüllrahmen der
  Zielecken). Commit `ab9f86b`.
- **Zurückgestellt** (auf Nutzerwunsch): Pixelmator-artige, automatisch
  einklappende Werkzeug-Seitenleiste. Nicht begonnen.
- Bereits vorher vorhanden und daher nicht erneut umgesetzt: ⌘Z/⌘Y visuell,
  Text-zu-Pfad, freies Verzerren samt Werkzeug, proportionale Skalierung mit
  Wahltaste, Cursor-Wechsel beim Verzerren.

### Problems.md behoben (Folgesitzung)
- **"Man kann nicht drag n drop machen"**: Es gab keinerlei
  Datei-Drag&Drop auf die Zeichenfläche. `CanvasView` registriert jetzt für
  `.fileURL`; eine hereingezogene PNG/JPEG-Datei wird als Bildknoten
  eingebettet, zentriert auf dem Ablagepunkt. Die Rahmenberechnung wurde
  dafür aus `DocumentWindowController.insertImage` in eine gemeinsame reine
  Funktion `ImagePlacement.frame(...)` gezogen (test-first,
  `ImagePlacementTests`, 3 Fälle).
- **"Eimer sollte alles innerhalb einer Abgrenzung einfärben"**: Der Eimer
  zeichnete bis dahin nur eine dicke Linie. Jetzt füllt ein Klick die von
  bestehenden Konturen umschlossene Fläche — Schnittmenge aller Konturen,
  die den Klickpunkt enthalten, abzüglich aller, die ihn nicht enthalten
  (neues `BucketFill.swift`, aufbauend auf der vorhandenen
  `BooleanOperator`-Maschinerie, bewusst kein pixelbasiertes Flood-Fill).
  Ohne umschliessende Kontur passiert nichts. Test-first, `BucketFillTests`,
  6 Fälle inkl. Überlapp/Schnittmenge, Alleinbereich/Differenz und
  evenOdd-Loch am Klickpunkt.
  Commit `6d69495`.

### Verifikation
Jeder Commit dieser Sitzung: `swift test` (247 → 256, alle grün) +
`xcodegen generate && xcodebuild -project Sceau.xcodeproj -scheme Sceau
-configuration Debug build` (BUILD SUCCEEDED). Kein GUI-Ende-zu-Ende-Test
mit echter Maussteuerung (siehe Standing-Constraint oben) — Eimer und
Drag&Drop sind daher nur durch die Kernlogik-Tests und den erfolgreichen
App-Build abgedeckt, nicht durch tatsächliches Klicken/Ziehen in der
laufenden App.

### Sonstiges
- Aktueller Stand als Release-Build nach `/Applications/Sceau.app` kopiert
  (`ditto`, `BUILT_PRODUCTS_DIR` über `xcodebuild -showBuildSettings`
  ermittelt).
