# Agent Rules — Sceau

Regeln für KI-Agenten (Claude Code o.ä.), die an diesem Projekt arbeiten. Ziel: effizientes, verlässliches Arbeiten ohne unnötige Rückfragen oder Umwege, aber auch ohne stillschweigende Fehlentscheidungen.

## 1. Test-first, immer

**Reihenfolge ist nicht verhandelbar: zuerst den Test schreiben, dann den Code, dann testen.**

Nicht: Code schreiben → Test schreiben → testen.
Sondern: Test schreiben (rot) → Code schreiben, bis der Test grün ist → laufen lassen und verifizieren.

- Für jede neue Funktion oder jeden Bugfix zuerst einen fehlschlagenden Test formulieren, der das gewünschte Verhalten (bzw. den Bug) präzise beschreibt.
- Erst danach die Implementierung schreiben — mit dem alleinigen Ziel, den Test grün zu bekommen.
- Test tatsächlich ausführen und das Ergebnis zeigen/berichten, nicht nur behaupten, dass er passt.
- Besonders wichtig für die Vektor-Pfad-Logik (Pfadberechnung, Bézier-Manipulation, Boolean-Operationen auf Formen, Export-Konvertierung) — hier sind Rundungs- und Edge-Case-Fehler leicht zu übersehen und teuer, wenn sie unbemerkt in den Export gelangen.
- Bei reinem UI-Code (SwiftUI-Paletten/Inspector), der schwer isoliert zu testen ist: zumindest die zugrundeliegende Logik (State, Berechnungen, Geometrie) test-first entwickeln; reine Layout-Anpassungen sind ausgenommen.
- Ausnahmen (z.B. explorativer Spike-Code, der danach verworfen wird) müssen explizit als solche benannt werden, bevor man von der Regel abweicht.

## 2. Kontext vor Code

- Vor Änderungen den Entwicklungsplan (`docs/entwicklungsplan.md`) und bestehenden Code lesen, statt Annahmen über Architektur oder Konventionen zu treffen.
- Bestehende Muster (Naming, Fehlerbehandlung, Architektur-Layer) übernehmen statt neue Stile einzuführen.
- Bei Unsicherheit über eine architekturrelevante Entscheidung (z.B. Datenmodell für Pfade/Ebenen, Export-Pipeline) nachfragen statt zu raten — solche Entscheidungen sind teuer zu revidieren.

## 3. Sparsamkeit bei Features

- Projektphilosophie: "Formen zuerst, Pfade zweitrangig. Ein Fenster, ein Fokus. Sofort exportierbar." Agenten sollen keine ungefragten Zusatzfeatures oder zusätzliche Menüebenen einbauen, auch wenn sie naheliegend erscheinen.
- Scope-Creep vermeiden: nur umsetzen, was explizit verlangt wurde oder zwingend zur Aufgabe gehört.

## 4. Präzision bei Geometrie & Export

- Numerische Genauigkeit bei Pfad-/Kurvenberechnungen nicht auf Kosten der Lesbarkeit opfern, aber Rundungsfehler und Edge Cases (z.B. entartete Kurven, Nullvektoren, sich selbst schneidende Pfade) bewusst testen.
- Export-Korrektheit (z.B. SVG/PDF-Konformität) hat Vorrang vor eleganter interner Repräsentation — im Zweifel gegen eine echte Datei/einen echten Viewer verifizieren, nicht nur gegen den eigenen Parser.

## 5. Kleine, überprüfbare Schritte

- Änderungen in kleinen, in sich abgeschlossenen Schritten liefern, die einzeln getestet und nachvollzogen werden können.
- Nach jedem Schritt kurz zusammenfassen, was geändert wurde und wie es verifiziert wurde (welcher Test, welches Ergebnis).
- Keine grossen, unangekündigten Refactorings "nebenbei" — separat vorschlagen und bestätigen lassen.

## 6. Kommunikation

- Ergebnisse ehrlich berichten: Wenn ein Test fehlschlägt oder ein Schritt übersprungen wurde, das klar sagen statt zu beschönigen.
- Bei architektonischen oder Scope-Fragen aktiv nachfragen statt anzunehmen.
- Deutsch als Projektsprache für Dokumentation/Kommunikation beibehalten (README ist auf Deutsch verfasst).
