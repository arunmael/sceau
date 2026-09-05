import AppKit
import SceauCore

/// Die vier booleschen Operationen der Werkzeugleiste.
///
/// Bewusst nur diese vier statt eines vollständigen Pathfinder-Panels — die
/// übrigen Varianten sind laut Entwicklungsplan Randfälle, die eine Logo-App
/// nicht braucht.
@MainActor
enum PathfinderCommands {

    /// Verhindert, dass ein zweites schnelles Tastenkürzel-Auslösen eine
    /// weitere, parallel laufende Verknüpfung auf womöglich schon
    /// veränderter Auswahl startet — ohne diese Sperre könnte eine zweite
    /// Operation IDs entfernen wollen, die die erste bereits ersetzt hat.
    private static var isBusy = false

    static func perform(
        _ operation: BooleanOperation,
        on store: DocumentStore,
        presentingIn window: NSWindow?
    ) {
        guard !isBusy else { return }

        let selected = store.document.nodes(with: store.selection)

        guard selected.count >= 2 else {
            present(
                message: "Mindestens zwei Objekte auswählen",
                detail: "Boolesche Operationen verknüpfen zwei oder mehr Formen miteinander.",
                in: window
            )
            return
        }

        // Das unterste Objekt ist das Subjekt, alle darüber sind der Gegenpart.
        // Beim Subtrahieren heisst das: was oben liegt, wird unten abgezogen —
        // dieselbe Erwartung, die Gestaltungsprogramme durchweg bedienen.
        let subjectNode = selected[0]
        let subject = NodeGeometry.path(for: subjectNode)
        let clip = VectorPath(
            subpaths: selected.dropFirst().flatMap { NodeGeometry.path(for: $0).subpaths }
        )

        let removedIDs = Set(selected.map(\.id))
        let resultStyle = subjectNode.style
        let resultName = name(for: operation)

        // Bei vielteiligen Logos kann die Verknüpfung spürbar rechnen. Sie läuft
        // deshalb abseits des Hauptthreads, damit die Oberfläche nicht einfriert
        // (Entwicklungsplan, Abschnitt 2.1).
        isBusy = true
        Task {
            defer { isBusy = false }
            let outcome: Result<VectorPath, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try BooleanOperator.apply(operation, subject: subject, clip: clip))
                } catch {
                    return .failure(error)
                }
            }.value

            switch outcome {
            case let .success(path):
                let node = Node(
                    name: resultName,
                    style: resultStyle,
                    content: .path(path)
                )
                store.apply(resultName) { document in
                    document.remove(ids: removedIDs)
                    // Weil die Ausgangsobjekte auf verschiedenen Ebenen liegen
                    // können, kommt ihr gemeinsames Ergebnis auf die Wurzelebene.
                    document.appendOnTop(node)
                }
                store.selection = [node.id]

            case let .failure(error):
                present(for: error, operation: operation, in: window)
            }
        }
    }

    private static func name(for operation: BooleanOperation) -> String {
        switch operation {
        case .union: return "Vereinigen"
        case .subtract: return "Subtrahieren"
        case .intersect: return "Schnittmenge"
        case .exclude: return "Ausschliessen"
        }
    }

    private static func present(for error: Error, operation: BooleanOperation, in window: NSWindow?) {
        let detail: String
        switch error {
        case BooleanError.emptyResult:
            detail = switch operation {
            case .intersect: "Die gewählten Formen überlappen sich nicht, es bleibt also keine gemeinsame Fläche übrig."
            case .subtract: "Das obere Objekt deckt das untere vollständig ab, es bleibt nichts übrig."
            default: "Die Verknüpfung ergibt keine Fläche."
            }
        case BooleanError.emptyInput:
            detail = "Mindestens eine der gewählten Formen hat keine Kontur."
        default:
            detail = "Die Verknüpfung konnte nicht berechnet werden."
        }

        present(message: "\(name(for: operation)) nicht möglich", detail: detail, in: window)
    }

    private static func present(message: String, detail: String, in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
