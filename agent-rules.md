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

## 7. Delegation an Codex (Credits sparen)

Ein MCP-Server `codex` steht bereit (lokal installierte OpenAI Codex CLI, eingeloggt via ChatGPT-Abo,
nicht über Claude-Credits abgerechnet). Er stellt einen vollwertigen Coding-Agenten mit Datei-/Shell-
Zugriff bereit, der Aufgaben in einem eigenen Working Directory bearbeitet.

Das passt direkt in Regel 1 (Test-first): Der fehlschlagende Test wird weiterhin zuerst und selbst
geschrieben — das ist die eigentliche Entwurfsentscheidung und bleibt bei mir. Erst danach kann die
Implementierung, die den Test grün bekommen soll, an Codex delegiert werden, statt sie selbst zu
schreiben.

**Wann delegieren (Default, nicht optional):** Standard-/Boilerplate-Implementierung mit bereits
geschriebenem Test und klarer Erwartung — CRUD-Code, Wiederholungen über mehrere Dateien,
Export-Konvertierungs-Boilerplate, Refactorings nach festem Muster. Kommentarlos selbst schreiben ist
keine gültige Option, wenn die Aufgabe darauf passt — Abweichung braucht eine kurze Begründung.

**Wann NICHT delegieren:** Architekturrelevante Entscheidungen (Datenmodell für Pfade/Ebenen,
Export-Pipeline, s. Regel 2), Kernlogik der Vektor-Pfad-Berechnung/Boolean-Operationen, alles mit
Rundungs-/Edge-Case-Risiko, das laut Regel 1 besondere Sorgfalt braucht, oder wo Kontext aus dem
Gespräch nötig ist, den Codex nicht hat. Im Zweifel selbst machen.

**Ablauf:** Test selbst schreiben → präzisen Sub-Auftrag an das `codex`-Tool (Zieldatei, Signaturen,
der Test, gegen den es laufen soll) → Ergebnis selbst prüfen (Diff lesen, Test tatsächlich ausführen,
nicht nur der Meldung von Codex glauben) → gemäss Regel 5 in kleinen Schritten berichten, was geändert
und wie verifiziert wurde.
