# Entwicklungsplan: Sceau — Logo- & Vektor-App für macOS

*App-Name: Sceau*

## 1. Vision

Eine native macOS-App für Vektorgrafik, fokussiert auf Logos, Icons und einfache Illustrationen. Kein Illustrator-Klon mit Mesh-Verläufen, Perspektivraster und 3D-Werkzeugen — sondern das Minimum, mit dem man von der Idee zu einem sauberen, exportierbaren Vektor-Logo kommt, ohne sich durch Menüs zu kämpfen.

**Leitsatz:** Wer diese App öffnet, soll in der ersten Minute ein Rechteck zeichnen, es einfärben und eine zweite Form dazu kombinieren können — ohne Handbuch.

## 2. Nicht verhandelbare Grundanforderungen

Wichtiger als jedes einzelne Feature: Die App muss stabil, effizient und ohne Abstürze laufen. Eine App, die abstürzt oder ruckelt, ist wertlos — egal wie clean die Oberfläche ist. Das steht über allem anderen in diesem Dokument.

### 2.1 Stabilität & Performance
- **Kein Datenverlust bei Absturz:** Autosave in kurzen Intervallen sowie bei Werkzeugwechseln; automatische Wiederherstellung offener Dokumente nach einem Crash
- **Mehrere Backups, automatisch und manuell:** Nicht nur ein einzelner Autosave-Stand — mehrere Versionen im Hintergrund behalten. Dafür bietet sich Apples eingebaute Dokumentenversionierung an (`NSDocument` mit aktiviertem Auto-Save liefert automatisch den bekannten "Alle Versionen durchsuchen..."-Zeitmaschine-Browser über `NSFileVersion`, kein Eigenbau nötig) — gerade bei Logos praktisch, um vor einer riskanten booleschen Operation einen Stand zu sichern. Zusätzlich ein manueller Befehl ("Version jetzt sichern"). Alte automatische Versionen nach sinnvoller Anzahl/Zeitspanne aufräumen, um Speicherplatz zu sparen
- **Speicher-Management bei komplexen Pfaden:** Boolesche Operationen (`BooleanPath`/`iOverlay`) können bei vielteiligen Logos rechenintensiv werden — deshalb asynchron im Hintergrund berechnen, damit die Oberfläche nicht einfriert
- **Fehler abfangen statt abstürzen:** Besonders beim SVG-Export (eigener Konverter!) und bei booleschen Operationen auf ungültigen oder selbstüberschneidenden Pfaden robust bleiben statt zu crashen; kein `try!`/erzwungenes Auspacken in produktivem Code
- **Automatisierte Tests** für die Pfad-Engine (Ankerpunkt-Editor, boolesche Operationen, Text-zu-Pfad) sowie Stresstests mit komplexen, vielteiligen Logos vor jedem Release
- **Crash-Reporting von Anfang an** (z. B. via `MetricKit`), um Probleme früh zu erkennen statt erst durch Nutzer-Beschwerden

### 2.2 Touch- und Apple-Pencil-Bedienung (iPad als erweiterter Bildschirm)
Seit macOS 27 „Golden Gate" unterstützt Sidecar per „Direct Touch" die direkte Fingerbedienung von Mac-Apps auf dem iPad — zusätzlich zum länger etablierten Apple Pencil. Konsequenzen für die App:

- **Apple Pencil:** Eignet sich besonders gut fürs präzise Setzen von Ankerpunkten und Kurvengriffen — Druck-/Neigungswerte über Standard-`NSEvent`-Tablet-APIs auswerten. Vektorpfade selbst kennen zwar keine Druckstärke, aber die Neigung liesse sich z. B. optional für die Konturstärke beim Zeichnen nutzen (kein MVP-Muss)
- **Direkte Fingerbedienung (macOS 27 + iPadOS 27, Apple-Silicon-Mac vorausgesetzt):** Ein Finger funktioniert automatisch wie ein Mauszeiger — Standard-AppKit-Controls (Buttons, Farbwähler, Ebenenliste) funktionieren dadurch bereits "gratis" ohne Zusatzaufwand
- **Wichtig für die eigene Canvas-Implementierung:** Ankerpunkte, Kurvengriffe und Werkzeug-Icons gross genug halten, damit Finger sie zuverlässig treffen — bei feinem Pfad-Editing ist das kritischer als bei einfacher Formmanipulation
- **Multitouch-Gesten** (Pinch-to-Zoom) über `NSMagnificationGestureRecognizer` einbinden
- **Für sehr präzises Pfad-Editing bleibt der Apple Pencil die bessere Wahl als der Finger** — die App sollte beide Eingabearten unterstützen, ohne sie künstlich gleich zu behandeln
- Voraussetzung: Mac mit Apple Silicon sowie ein iPad mit iPadOS 27, verbunden über Sidecar

## 3. Zielgruppe & Anwendungsfälle

- Leute, die ein eigenes Logo, App-Icon oder Wortmarke selbst gestalten wollen
- Einfache Icon-Sets für eigene Projekte (z. B. für deine eigenen macOS-Apps)
- Kein Zielpublikum: professionelle Illustrator:innen mit komplexen, mehrfarbigen Grossformat-Illustrationen oder Verpackungsdesign — dafür bleibt Illustrator die richtige Wahl

## 4. Design-Prinzipien

1. **Formen zuerst, Pfade zweitrangig:** Die meisten Logos entstehen aus Grundformen + Kombinieren, nicht aus komplexem Freihandzeichnen. Die App soll das widerspiegeln.
2. **Ein Fenster, ein Fokus:** Gleiches Layout-Prinzip wie bei der Foto-App — Canvas mittig, Ebenen auf einer Seite, Eigenschaften kontextabhängig auf der anderen.
3. **Wenige, aber präzise Zahlenwerte:** Wo Pixel-genaue Positionierung zählt (Icon-Design!), müssen exakte Werte eingebbar sein — aber nur dort, nicht als Standard-Eingabemethode für alles.
4. **Sofort exportierbar:** Von der ersten Form bis zum fertigen SVG/PNG soll es nie mehr als ein, zwei Klicks brauchen.
5. **Optik:** Gleiche Liquid-Glass-Sprache wie die Foto-App — beide Apps sollen sich wie aus einer Familie anfühlen.

## 5. Feature-Set (MVP) — was wirklich rein muss

### 5.1 Grundformen
- Rechteck (mit einstellbarem Eckradius), Ellipse/Kreis, Polygon, Stern (mit Zacken-Anzahl-Regler)
- Direkt auf dem Canvas skalier- und verschiebbar mit sichtbaren Griffpunkten

### 5.2 Zeichenstift (vereinfacht)
- Ankerpunkte setzen per Klick, Kurven durch Ziehen (Standard-Bézier-Verhalten)
- Ankerpunkte nachträglich verschieben, Kurvengriffe anpassen
- Pfad schliessen/offen lassen
- **Bewusst kein** eigenes Kalligrafie-/Formpinsel-Werkzeug wie in Illustrator

### 5.3 Boolesche Operationen (Pathfinder — reduziert)
Nur die vier, die man wirklich ständig braucht:
- Vereinigen
- Subtrahieren
- Schnittmenge
- Ausschliessen (XOR)

Kein vollständiges Pathfinder-Panel mit 10+ Optionen wie in Illustrator.

### 5.4 Farbe, Kontur & Verläufe
- Flächenfarbe (Farbwähler + Hex-Eingabe)
- Konturfarbe, -stärke, -art (durchgezogen/gestrichelt)
- Einfacher linearer und radialer Verlauf mit 2–3 Farbstopps — **kein** Mesh-Verlauf

### 5.5 Ebenen & Gruppierung
- Ebenenliste wie in der Foto-App: Vorschau, Sichtbarkeit, Umbenennen, Reihenfolge per Drag & Drop
- Formen zu Gruppen zusammenfassen (wichtig für Logos aus mehreren Elementen)

### 5.6 Ausrichtung & Anordnung
- Ausrichten (links/mittig/rechts, oben/mittig/unten)
- Gleichmässig verteilen
- Snapping am Raster und an anderen Objektkanten
- Spiegeln horizontal/vertikal (für symmetrische Logos sehr häufig gebraucht)

### 5.7 Text
- Textebene mit Schrift, Grösse, Farbe, Zeichen-/Wortabstand (Basis-Kerning)
- Text in Pfade umwandeln (wichtig für Logo-Export, damit Schriften beim Teilen nicht fehlen)
- **Kein** Text-auf-Pfad, keine Absatzformatierung — das ist Layout-Funktionalität, kein Logo-Werkzeug

### 5.8 Zeichenfläche
- Eine Arbeitsfläche pro Dokument mit frei wählbarer Grösse plus Presets (App-Icon 1024×1024, Favicon, Social-Media-Profilbild)
- **Kein** Multi-Artboard-System wie in Illustrator — falls später gebraucht, kommt es in v2

### 5.9 Export
- SVG (editierbare Vektordaten)
- PDF (verlustfrei, druckfähig)
- PNG in mehreren Auflösungen gleichzeitig (praktisch für App-Icon-Sets: 16/32/64/128/256/512/1024 px in einem Export-Vorgang)

## 6. Bewusst NICHT im Funktionsumfang (v1)

- Mesh-Verläufe und komplexe Verlaufswerkzeuge
- Perspektivraster, 3D/Turntable-Funktionen
- Musterfüllungen mit eigenem Pattern-Editor
- Mehrere Zeichenflächen pro Dokument
- KI-Vektorisierung (Skizze/Foto → Vektor) — spannend, aber ein eigenes Projekt für später, kein MVP-Feature
- Kalligrafie-/Formpinsel
- Volles Pathfinder-Panel mit Randfällen-Optionen
- Plugin-System

## 7. Technische Architektur

### 7.1 Framework-Wahl
- **Swift**, konsistent mit deinen anderen Projekten
- Canvas als **AppKit** (`NSView`-basiert), da hier volle Kontrolle über Ankerpunkt-Interaktion, Griffpunkte und Snapping nötig ist
- Paletten/Inspector wieder als **SwiftUI**, eingebettet per `NSHostingView` — gleiches Muster wie bei der Foto-App, spart Zeit und sorgt für konsistentes Look-and-Feel zwischen beiden Apps

### 7.2 Rendering
- Jede Form/jeder Pfad wird intern als eigenes Datenmodell aus Ankerpunkten + Kontrollpunkten gehalten (nicht direkt als `CGPath`, da `CGPath` unveränderlich ist und für Live-Editing eine eigene, editierbare Zwischenrepräsentation braucht)
- Zur Darstellung wird daraus pro Frame ein `CGPath` gebaut und über **`CAShapeLayer`** gerendert — das ist der natürliche macOS-Weg für Vektorformen: GPU-komponiert, performant, direkt mit Fläche/Kontur/Verlauf kompatibel
- Seit macOS 14 (Sonoma) bringt `NSBezierPath` eine eingebaute `cgPath`-Eigenschaft mit, was die Konvertierung deutlich vereinfacht gegenüber älteren manuellen Lösungen

### 7.3 Boolesche Operationen — konkrete Umsetzung
Das ist der technisch anspruchsvollste Teil, da AppKit dafür keine native API mitbringt. Zwei realistische Wege:
- **`BooleanPath`** (Swift Package, `Kyome22/BooleanPath`): direkte Erweiterung von `NSBezierPath` um `.union()`, `.intersection()`, `.subtraction()`, `.difference()` — eine Swift-Neuauflage von Andy Finnells klassischer „VectorBoolean"-Bibliothek, speziell für macOS
- **`iOverlay`** (`iShape-Swift/iOverlay`): moderneres, aktiv gepflegtes Package für Polygon-Boolesche-Operationen direkt auf `CGPath`-Basis, inklusive Umgang mit Löchern und Selbstüberschneidungen

Empfehlung: mit `BooleanPath` starten (einfachere API, direkt auf `NSBezierPath`), bei Performance-/Robustheitsproblemen später auf `iOverlay` wechseln.

### 7.4 Text
- **Core Text** für Rendering und Messung
- Umwandlung „Text zu Pfaden" über `CTFontCreatePathForGlyph` — jeder Buchstabe wird zu einem eigenen bearbeitbaren Pfad

### 7.5 Export-Umsetzung
- **PDF:** nativ über `CGContext`/`NSPrintOperation` — macOS' Grafiksystem ist im Kern selbst PDF-fähig, das ist praktisch geschenkt
- **PNG:** Rasterisierung des `CGContext` in gewünschter Pixelgrösse, mehrere Grössen in einem Durchlauf für Icon-Sets
- **SVG:** kein natives Export-API vorhanden — eigener, aber überschaubarer Konverter nötig, der die internen Pfad-/Formdaten in SVG-Pfad-Strings (`M`, `L`, `C`, `Z`) übersetzt

### 7.6 Datenmodell & Speicherung
- `NSDocument`-basiert, Objektbaum aus Formen/Pfaden/Gruppen/Text als eigenes Projektformat (JSON-Struktur)
- `NSUndoManager` für Undo/Redo

## 8. UI-Konzept (grob)

```
┌─────────────────────────────────────────────────┐
│  Werkzeugleiste (kontextabhängig)                │
├───────────┬───────────────────────┬─────────────┤
│  Ebenen   │                       │  Eigenschaften│
│  (Liste)  │        Canvas         │  Fläche/Kontur│
│           │      (Zeichenfläche)  │  Verlauf,     │
│           │                       │  Position,    │
│           │                       │  Grösse        │
└───────────┴───────────────────────┴─────────────┘
```
- Werkzeugleiste oben: Auswählen, Formen (Untermenü Rechteck/Ellipse/Polygon/Stern), Zeichenstift, Text, Pathfinder-Operationen, Ausrichten — max. 6–7 sichtbare Icons
- Eigenschaften-Panel rechts zeigt je nach Auswahl Fläche/Kontur/Verlauf (bei Formen) oder Schrift-Optionen (bei Text)

## 9. Entwicklungs-Roadmap

**Phase 0 — Grundgerüst**
Dokumentarchitektur, Canvas mit `CAShapeLayer`-Rendering, Ebenenliste

**Phase 1 — MVP: Formen & Farbe**
Grundformen zeichnen/skalieren/verschieben, Flächenfarbe + Kontur, Ausrichtungswerkzeuge, PNG-/PDF-Export

**Phase 2 — Zeichenstift & Boolesche Operationen**
Ankerpunkt-Editor, Bézier-Kurven, Integration von `BooleanPath` für Vereinigen/Subtrahieren/Schnittmenge/Ausschliessen

**Phase 3 — Text & Verläufe**
Textebenen, Text-zu-Pfad-Umwandlung, lineare/radiale Verläufe, SVG-Exporter

**Phase 4 — Politur & optional**
Icon-Set-Export mit mehreren Grössen gleichzeitig, Tastenkürzel, ggf. iPad-Version, ggf. gemeinsames Austauschformat mit der Foto-App (z. B. fertiges Logo als Ebene in eine Collage importieren)

## 10. Offene Entscheidungen

- ~~Name der App~~ → entschieden: **Sceau**
- Vertrieb: Mac App Store vs. eigenständig
- Preismodell
- Ob `BooleanPath` für den Start ausreicht oder gleich `iOverlay` sinnvoller ist (am besten früh mit ein paar komplexeren Testformen ausprobieren)
