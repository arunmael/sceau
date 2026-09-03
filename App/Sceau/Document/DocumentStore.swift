import AppKit
import Observation
import SceauCore

/// Das aktive Werkzeug der Werkzeugleiste.
enum ToolKind: String, CaseIterable, Identifiable {
    case select
    case rectangle
    case ellipse
    case polygon
    case star
    case pen
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Auswählen"
        case .rectangle: return "Rechteck"
        case .ellipse: return "Ellipse"
        case .polygon: return "Polygon"
        case .star: return "Stern"
        case .pen: return "Zeichenstift"
        case .text: return "Text"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .polygon: return "pentagon"
        case .star: return "star"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        }
    }

    /// Werkzeuge, die durch Aufziehen eine neue Grundform erzeugen.
    var createsShape: Bool {
        switch self {
        case .rectangle, .ellipse, .polygon, .star: return true
        case .select, .pen, .text: return false
        }
    }
}

/// Der gemeinsame Zustand eines geöffneten Dokuments: Modell, Auswahl und
/// aktives Werkzeug — plus die Undo-Registrierung.
///
/// Canvas (AppKit) und Paletten (SwiftUI) arbeiten beide ausschliesslich über
/// diesen Store, damit es nur **eine** Wahrheit gibt und beide Seiten
/// automatisch synchron bleiben.
///
/// ## Warum Undo über ganze Schnappschüsse
/// Jede Änderung legt eine Kopie des vorherigen ``Document`` auf den
/// Undo-Stapel, statt für jede Operation eine eigene Gegenoperation zu
/// schreiben. Das ist die mit Abstand fehlerärmste Variante — invertierbare
/// Einzeloperationen sind eine klassische Bugquelle — und dank Copy-on-Write
/// bei Logo-Dokumenten auch billig genug: ungeänderte Teilbäume teilen sich
/// den Speicher.
@MainActor
@Observable
final class DocumentStore {
    /// Das Dokumentmodell. Änderungen laufen ausschliesslich über ``apply(_:_:)``,
    /// damit kein Schritt ohne Undo-Eintrag passiert.
    private(set) var document: Document

    /// IDs der ausgewählten Knoten.
    var selection: Set<UUID> = []

    /// Aktives Werkzeug.
    var activeTool: ToolKind = .select

    /// Zoomfaktor der Ansicht (1 = 100 %). Gehört zum Ansichtszustand, nicht
    /// zum Dokument, und wird deshalb nicht mitgespeichert.
    var zoom: CGFloat = 1

    /// Der Undo-Manager des zugehörigen `NSDocument`.
    weak var undoManager: UndoManager?

    /// Wird nach jeder Änderung aufgerufen, damit das `NSDocument` sich als
    /// geändert markieren und den Autosave anstossen kann.
    var didChange: (@MainActor () -> Void)?

    init(document: Document) {
        self.document = document
    }

    // MARK: - Änderungen

    /// Führt eine Änderung am Dokument aus und macht sie widerrufbar.
    ///
    /// - Parameters:
    ///   - actionName: Menütext für „Widerrufen …", auf Deutsch und in der
    ///     Grundform, z. B. „Form bewegen".
    ///   - mutate: Die Änderung am Modell.
    func apply(_ actionName: String, _ mutate: (inout Document) -> Void) {
        let before = document
        var draft = document
        mutate(&draft)

        // Änderungen, die nichts ändern, dürfen keinen Undo-Schritt erzeugen —
        // sonst sammelt sich beim blossen Anklicken von Objekten Leerlauf an.
        guard draft != before else { return }

        document = draft
        registerUndo(restoring: before, actionName: actionName)
        didChange?()
    }

    /// Schreibt das Modell **ohne** Undo-Eintrag.
    ///
    /// Nur für Zwischenstände während einer laufenden Zugbewegung gedacht: Dort
    /// würde jeder Mausschritt sonst einen eigenen Undo-Eintrag erzeugen. Der
    /// Aufrufer ist dafür verantwortlich, am Ende genau einen Schritt über
    /// ``apply(_:_:)`` festzuschreiben.
    func setDocumentWithoutUndo(_ newValue: Document) {
        guard newValue != document else { return }
        document = newValue
        didChange?()
    }

    private func registerUndo(restoring snapshot: Document, actionName: String) {
        guard let undoManager else { return }

        undoManager.registerUndo(withTarget: self) { store in
            // Der Handler wird von AppKit auf dem Hauptthread aufgerufen; das
            // ist dem Compiler aber nicht bekannt, daher die Zusicherung.
            MainActor.assumeIsolated {
                let redoSnapshot = store.document
                store.document = snapshot
                store.pruneSelection()
                store.registerUndo(restoring: redoSnapshot, actionName: actionName)
                store.didChange?()
            }
        }
        undoManager.setActionName(actionName)
    }

    /// Entfernt Auswahl-IDs, zu denen es nach einer Änderung keinen Knoten mehr
    /// gibt — etwa nach dem Widerrufen eines Einfügens.
    private func pruneSelection() {
        let existing = Set(document.nodes.flatMap { $0.flattenedIDs })
        selection.formIntersection(existing)
    }

    // MARK: - Auswahl

    var selectedNodes: [Node] {
        document.nodes.filter { selection.contains($0.id) }
    }

    func select(_ id: UUID, extending: Bool) {
        if extending {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    func selectAll() {
        selection = Set(document.nodes.map(\.id))
    }

    func clearSelection() {
        selection.removeAll()
    }
}

extension Node {
    /// Die eigene ID sowie die aller Nachfahren.
    var flattenedIDs: [UUID] {
        guard let children else { return [id] }
        return [id] + children.flatMap(\.flattenedIDs)
    }
}
