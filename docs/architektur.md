# Architektur

Ergänzt den [Entwicklungsplan](entwicklungsplan.md) um die Entscheidungen, die
beim Bauen tatsächlich getroffen wurden — jeweils mit Begründung, damit später
nachvollziehbar ist, warum etwas so und nicht anders aussieht.

## Aufteilung in zwei Schichten

```
SceauCore   (Swift Package)   reine Logik, kein AppKit
   ↑
Sceau       (App-Ziel)        AppKit-Canvas + SwiftUI-Paletten
```

`SceauCore` hängt nur von CoreGraphics, CoreText, ImageIO und `iOverlay` ab —
**nicht** von AppKit. Das ist keine Kosmetik: Nur dadurch lässt sich die gesamte
Geometrie-, Boolean- und Exportlogik mit `swift test` von der Kommandozeile
prüfen, ohne eine App zu starten. Genau diese Teile sind laut
[agent-rules.md](../agent-rules.md) diejenigen, bei denen Rundungs- und
Randfehler teuer werden.

Das Xcode-Projekt wird aus [`project.yml`](../project.yml) mit **XcodeGen**
erzeugt und ist deshalb nicht versioniert:

```bash
xcodegen generate
```

## Koordinatensystem: Ursprung links oben, y nach unten

Verbindlich für das gesamte Projekt. Entspricht SVG und den üblichen
Gestaltungswerkzeugen.

Der Grund ist der Export: Bei einer App, deren Kernzweck ein sauberes SVG ist,
wiegt eine spiegelungsfreie Exportstrecke schwerer als die Nähe zur
AppKit-Vorgabe (die links **unten** beginnt). Der Preis sind genau zwei Stellen,
die umrechnen müssen, und beide sind durch Tests abgesichert:

| Stelle | Umrechnung |
|---|---|
| `CanvasView` | `isFlipped == true` |
| `DocumentRenderer` (PDF/PNG) | einmalig `translateBy` + `scaleBy(x: 1, y: -1)` |
| `TextToPath` | Glyphen an der Grundlinie spiegeln (CoreText liefert y nach oben) |
| `SVGExporter` | **keine** — 1:1, genau der Zweck der Konvention |

## Dokumentmodell als Werttyp

`Document` → `[Node]` → `Node.Content` (`.shape` / `.path` / `.text` / `.group`)
sind durchgehend `struct`/`enum`, nicht Klassen.

Konsequenzen, die das erst ermöglicht:
- **Undo über Schnappschüsse** statt invertierbarer Einzeloperationen. Jede
  Änderung legt eine Kopie des vorherigen Dokuments auf den Undo-Stapel. Selbst
  geschriebene Gegenoperationen sind eine klassische Fehlerquelle; dank
  Copy-on-Write ist der Schnappschuss bei Dokumentgrössen dieser App billig.
- `Codable` ohne Handarbeit → das Dateiformat ist schlicht JSON.
- `Sendable` → boolesche Operationen können ohne Weiteres auf einen
  Hintergrund-Thread ausgelagert werden.

### Keine allgemeine Transformationsmatrix
Knoten tragen nur einen Rotationswinkel. Verschieben und Skalieren wird direkt
in die Geometrie geschrieben (`ShapeSpec.frame` bzw. Ankerkoordinaten). Das
erspart die gesamte Fehlerklasse verschachtelter, zusammengesetzter
Transformationen; Scherung braucht eine Logo-App nicht.

### Grundformen bleiben parametrisch
Ein Rechteck bleibt ein `ShapeSpec.rectangle(frame:cornerRadius:)` und wird erst
bei Bedarf über `ShapeGeometry` zu Ankern aufgelöst. Nur so bleiben Eckradius,
Eckenzahl und Zackentiefe nachträglich im Inspektor einstellbar — „Formen
zuerst, Pfade zweitrangig".

## Boolesche Operationen: Polyzug statt Kurven

`iOverlay` rechnet auf Polygonen. Kurven werden deshalb vor der Operation
adaptiv abgeflacht (`Flattener`, Vorgabetoleranz 0.05 pt), und **das Ergebnis
bleibt ein Polyzug**.

Bewusst entschieden gegen ein Zurückfitten von Bézierkurven: Das wäre ein
eigener, fehleranfälliger Algorithmus. Die Toleranz ist deshalb überall ein
Parameter und nirgends fest verdrahtet — ein späteres Refitting lässt sich
ergänzen, ohne Aufrufstellen anzufassen.

**Bekannte Einschränkung:** Nach einer Pathfinder-Operation sind die Anker
Eckpunkte, keine Kurvengriffe mehr. Das SVG wird dadurch grösser, sieht bei
normaler Betrachtung aber identisch aus.

**Umlaufrichtung:** `iOverlay` liefert Aussenkontur und Löcher mit
entgegengesetztem Drehsinn; die Richtung wird unverändert übernommen. Zusammen
mit der Füllregel `nonZero` bleiben Löcher dadurch Löcher. Code, der die
Richtung auswertet, darf **nicht** annehmen, dass die Aussenkontur ein
positives Shoelace-Vorzeichen hat — in dieser y-nach-unten-Konvention ist es
negativ.

## Undo während einer Zugbewegung

Beim Ziehen einer Form darf nicht jeder Mausschritt einen Undo-Eintrag
erzeugen. Der Canvas merkt sich deshalb den Ausgangsstand, schreibt
zwischendurch über `setDocumentWithoutUndo(_:)` und schreibt erst beim
Loslassen **einen** Schritt über `apply(_:_:)` fest.

## Sicherheitsnetz gegen Datenverlust

Umgesetzt über `NSDocument` statt Eigenbau:
- `autosavesInPlace = true` → automatische Sicherung und Wiederherstellung nach
  einem Absturz
- `preservesVersions = true` → der eingebaute Versionsbrowser
  („Ablage › Alle Versionen durchsuchen …")
- „Version jetzt sichern" (⌥⌘S) als ausdrücklicher Wiederherstellungspunkt vor
  riskanten Schritten

## Einrasten

Beim Bewegen rastet der **gemeinsame Hüllrahmen** der Auswahl ein, nicht jedes
Objekt einzeln — sonst zerrisse eine Mehrfachauswahl. Kandidaten sind Kanten
und Mitten der übrigen Objekte, die Zeichenfläche selbst sowie das Raster,
wobei echte Objektkanten Vorrang vor Rasterlinien haben.

Die gedrückte Befehlstaste schaltet das Einrasten für einen Zug vollständig ab.
Das wird in der Zeichenfläche entschieden und nicht über die Schalter in
`SnapSettings`: Dort bleibt die Zeichenfläche bewusst immer ein Ziel, und
genau die soll bei gedrückter Befehlstaste ebenfalls nicht fangen.

Die Fangweite ist in Dokumentpunkten angegeben und wird durch den Zoomfaktor
geteilt, damit sie auf dem Bildschirm konstant bleibt.

## Zeichenstift

Die Griff-Semantik liegt als Werttyp (`PenDraft`) im Kern, nicht als Zustand in
der Zeichenfläche — nur so lässt sich der heikle Teil ohne laufende Oberfläche
prüfen. Klicken setzt Eckpunkte, Ziehen erzeugt symmetrische Griffe, ein Klick
auf den ersten Anker schliesst den Pfad, Zeilenschalter beendet ihn offen.

Die Nachbearbeitung bestehender Pfade läuft über dasselbe Werkzeug: Ist ein
Pfad ausgewählt und der Zeichenstift aktiv, zeigt die Zeichenfläche Anker und
Kurvengriffe statt der Skaliergriffe. `VectorPath.movingHandle(_:at:to:)` hält
dabei die Regeln aus `AnchorStyle` ein — bei `.symmetric` wird der Gegengriff
gespiegelt, bei `.smooth` nur mitgedreht, bei `.corner` bleibt er unberührt.

## Absturzerfassung

Über `MetricKit` statt eines eigenen Absturzfängers, der dem System nur in die
Quere käme. Die Berichte landen als JSON im Programmunterstützungsordner
innerhalb des Sandbox-Containers.

**Noch offen:** Es gibt keinen Server, an den sie gehen. Das kommt, sobald der
Vertriebsweg entschieden ist; bis dahin sind die lokalen Dateien der Weg, um
nach einem Absturz nachzusehen.

## Offene Punkte

- Kurven-Refitting nach booleschen Operationen
- Zusammenfassen von Undo-Schritten beim Ziehen an Reglern im Inspektor
- Versand der Diagnoseberichte (siehe oben)
- Der Zeichenstift kann bestehende Pfade bearbeiten, aber noch keine Anker
  hinzufügen oder entfernen
- Verläufe werden im Inspektor bearbeitet, aber nicht direkt auf der
  Zeichenfläche
