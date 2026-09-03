# Sceau

Eine native macOS-App für Vektorgrafik, fokussiert auf Logos, Icons und einfache Illustrationen — das Minimum, mit dem man von der Idee zu einem sauberen, exportierbaren Vektor-Logo kommt, ohne sich durch Menüs zu kämpfen.

Formen zuerst, Pfade zweitrangig. Ein Fenster, ein Fokus. Sofort exportierbar.

## Status

Lauffähiger Stand: Die App startet, zeichnet, verknüpft Formen boolesch und
exportiert nach SVG, PDF und PNG.

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

## Lizenz

Copyright © 2026 Arun Meyer. Alle Rechte vorbehalten. Siehe [LICENSE](LICENSE) — dies ist **kein** Open-Source-Projekt; der Code ist einsehbar, aber nicht zur Nutzung, Kopie oder Weiterverbreitung freigegeben.
