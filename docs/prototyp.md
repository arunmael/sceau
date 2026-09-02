# Interaktiver Prototyp

**Link:** https://claude.ai/code/artifact/3e52bb1a-2f82-4082-92c9-e057fc000277

Klickbares HTML/JS-Modell des Interaktionskonzepts aus [`entwicklungsplan.md`](entwicklungsplan.md), gebaut um das UX zu testen, bevor dafür Swift/AppKit-Code entsteht. Läuft im Browser, kein Teil des späteren Xcode-Projekts.

## Was echt funktioniert

- Werkzeugleiste mit Formen-Flyout (Rechteck/Ellipse/Polygon/Stern), max. 7 sichtbare Icons — wie in Abschnitt 8 des Plans vorgesehen
- Formen zeichnen, verschieben, per Eckgriffen skalieren
- Ebenenliste: Sichtbarkeit, Umbenennen, Drag-&-Drop-Reihenfolge
- Eigenschaften-Panel: Position/Grösse, Eckradius/Ecken/Zacken, Fläche, Kontur
- **Pathfinder mit echter Polygon-Boolescher-Verknüpfung** (Vereinigen/Subtrahieren/Schnittmenge/XOR) über [polybooljs](https://github.com/velipso/polybooljs) — inkl. sauberem Abfangen von "kein Überlappungsbereich" statt Absturz
- Ausrichten/Verteilen/Spiegeln
- Undo (Cmd/Ctrl+Z), Autosave in `localStorage`
- SVG-Code-Ansicht als Vorschau auf den geplanten Exporter (Abschnitt 7.5)

## Was bewusst nicht simuliert ist

Zeichenstift, Text, Verläufe, echter Datei-Export — diese Teile entstehen laut Roadmap erst in Phase 2–4 und sind im Prototyp entsprechend gesperrt/ausgeblendet.

## Warum kein echter Xcode-Prototyp

AppKit/SwiftUI/Core Text laufen nicht ausserhalb von macOS; dieser Web-Prototyp testet daher nur das Interaktionsmodell, nicht die spätere native Umsetzung.
