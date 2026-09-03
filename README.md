# Sceau

Eine native macOS-App für Vektorgrafik, fokussiert auf Logos, Icons und einfache Illustrationen — das Minimum, mit dem man von der Idee zu einem sauberen, exportierbaren Vektor-Logo kommt, ohne sich durch Menüs zu kämpfen.

Formen zuerst, Pfade zweitrangig. Ein Fenster, ein Fokus. Sofort exportierbar.

## Status

Der Funktionsumfang aus Abschnitt 5 des Entwicklungsplans ist umgesetzt:
Grundformen, Zeichenstift samt Ankerbearbeitung, die vier
Pathfinder-Operationen, Farbe/Kontur/Verläufe, Ebenen und Gruppen,
Ausrichten/Verteilen/Spiegeln/Einrasten, Text mitsamt Umwandlung in Pfade,
Zeichenfläche mit Vorgabegrössen sowie Export nach SVG, PDF und PNG samt
Icon-Satz.

Der vollständige Entwicklungsplan (Vision, Feature-Set, Roadmap) liegt in
[`docs/entwicklungsplan.md`](docs/entwicklungsplan.md), die beim Bauen
getroffenen Entscheidungen in [`docs/architektur.md`](docs/architektur.md).
Die Roadmap-Phasen sind als [Milestones](https://github.com/arunmael/sceau/milestones)
im Repo abgebildet.

Ein interaktiver Web-Prototyp des Interaktionskonzepts steht unter
[`docs/prototyp.md`](docs/prototyp.md) — er diente als UX-Test vor der
Swift-Umsetzung und ist selbst kein Teil davon.

## Aufbau

```
SceauCore   (Swift Package)   Geometrie, Modell, Boolean, Export — ohne AppKit
Sceau       (App-Ziel)        AppKit-Canvas + SwiftUI-Paletten
```

`SceauCore` hängt nicht von AppKit ab und ist deshalb vollständig von der
Kommandozeile testbar — genau die Teile, in denen Rundungs- und Randfehler teuer
werden.

## Bauen

Voraussetzungen: Xcode 26 oder neuer, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
xcodegen generate
open Sceau.xcodeproj
```

`Sceau.xcodeproj` wird aus [`project.yml`](project.yml) erzeugt und ist nicht
versioniert — Quelle der Wahrheit ist allein die YAML-Datei.

Die Kernlogik ohne Xcode testen:

```bash
swift test
```

Es gibt bewusst **kein** Test-Ziel im Xcode-Projekt; die Gründe stehen in
[`docs/architektur.md`](docs/architektur.md).

## Das App-Icon

Das Programmsymbol ist selbst ein Sceau-Dokument
([`Design/AppIcon.sceau`](Design/AppIcon.sceau)) und wird mit Sceau' eigener
Exportstrecke erzeugt — es lässt sich also in der App öffnen und ändern:

```bash
swift run sceau-icon .
```

Damit ist es reproduzierbar und zugleich ein laufender Praxistest von
Grundformen, boolescher Verknüpfung, Verlauf und Rasterexport.

## Lizenz

Copyright © 2026 Arun Meyer. Alle Rechte vorbehalten. Siehe [LICENSE](LICENSE) — dies ist **kein** Open-Source-Projekt; der Code ist einsehbar, aber nicht zur Nutzung, Kopie oder Weiterverbreitung freigegeben.
