import CoreGraphics
import Foundation
import Observation

/// Das aktive Werkzeug der Werkzeugleiste.
public enum ToolKind: String, CaseIterable, Identifiable {
    case select
    case rectangle
    case ellipse
    case polygon
    case star
    case pen
    case text

    public var id: String { rawValue }

    public var title: String {
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

    public var symbolName: String {
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
    public var createsShape: Bool {
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
public final class DocumentStore {
    /// Das Dokumentmodell. Änderungen laufen ausschliesslich über ``apply(_:_:)``,
    /// damit kein Schritt ohne Undo-Eintrag passiert.
    public private(set) var document: Document

    /// IDs der ausgewählten Knoten.
    public var selection: Set<UUID> = []

    /// Aktives Werkzeug.
    public var activeTool: ToolKind = .select

    /// Zoomfaktor der Ansicht (1 = 100 %). Gehört zum Ansichtszustand, nicht
    /// zum Dokument, und wird deshalb nicht mitgespeichert.
    public var zoom: CGFloat = 1

    /// Ob das Raster gezeichnet wird.
    public var showsGrid = false

    /// Rasterweite in Dokumentpunkten.
    public var gridSize: CGFloat = 8

    /// Ob überhaupt eingerastet wird. Die Befehlstaste hebelt das zusätzlich
    /// für einen einzelnen Zug aus.
    public var snapsEnabled = true

    /// Der Undo-Manager des zugehörigen `NSDocument`.
    public weak var undoManager: UndoManager?

    /// Wird nach jeder Änderung aufgerufen, damit das `NSDocument` sich als
    /// geändert markieren und den Autosave anstossen kann.
    public var didChange: (@MainActor () -> Void)?

    /// Läuft gerade eine zusammengefasste Änderungsfolge, steht hier ihr Name
    /// und der Stand, auf den ein Widerrufen zurückführen soll.
    private var coalescing: (name: String, baseline: Document)?

    public init(document: Document) {
        self.document = document
    }

    // MARK: - Änderungen

    /// Führt eine Änderung am Dokument aus und macht sie widerrufbar.
    ///
    /// - Parameters:
    ///   - actionName: Menütext für „Widerrufen …", auf Deutsch und in der
    ///     Grundform, z. B. „Form bewegen".
    ///   - mutate: Die Änderung am Modell.
    public func apply(_ actionName: String, _ mutate: (inout Document) -> Void) {
        let before = document
        var draft = document
        mutate(&draft)

        // Änderungen, die nichts ändern, dürfen keinen Undo-Schritt erzeugen —
        // sonst sammelt sich beim blossen Anklicken von Objekten Leerlauf an.
        guard draft != before else { return }

        // Innerhalb einer zusammengefassten Folge wird ohne Undo geschrieben;
        // der eine Schritt entsteht erst beim Abschluss.
        guard coalescing == nil else {
            document = draft
            didChange?()
            return
        }

        document = draft
        registerUndo(restoring: before, actionName: actionName)
        didChange?()
    }

    /// Beginnt eine zusammengefasste Änderungsfolge.
    ///
    /// Gedacht für Zugbewegungen an Reglern: Ohne das ergäbe jeder
    /// Zwischenwert einen eigenen Undo-Schritt, und ein einziges Ziehen am
    /// Deckkraftregler würde die gesamte Widerrufsliste fluten. Zu jedem
    /// Aufruf gehört genau ein ``endCoalescing()``.
    public func beginCoalescing(_ actionName: String) {
        guard coalescing == nil else { return }
        coalescing = (actionName, document)
    }

    /// Schliesst die Folge ab und schreibt sie als **einen** Undo-Schritt fest.
    public func endCoalescing() {
        guard let session = coalescing else { return }
        coalescing = nil

        let result = document
        guard result != session.baseline else { return }

        // Kurz auf den Ausgangsstand zurück, damit `apply` den Schritt sauber
        // gegen die richtige Grundlage registriert.
        document = session.baseline
        apply(session.name) { $0 = result }
    }

    /// Schreibt das Modell **ohne** Undo-Eintrag.
    ///
    /// Nur für Zwischenstände während einer laufenden Zugbewegung gedacht: Dort
    /// würde jeder Mausschritt sonst einen eigenen Undo-Eintrag erzeugen. Der
    /// Aufrufer ist dafür verantwortlich, am Ende genau einen Schritt über
    /// ``apply(_:_:)`` festzuschreiben.
    public func setDocumentWithoutUndo(_ newValue: Document) {
        guard newValue != document else { return }
        document = newValue
        didChange?()
    }

    private func registerUndo(restoring snapshot: Document, actionName: String) {
        guard let undoManager else { return }

        // `UndoManager` verlangt eine offene Gruppe, sonst wirft er beim
        // Registrieren. Im laufenden Programm öffnet AppKit sie pro Durchlauf
        // der Ereignisschleife selbst; ausserhalb davon — etwa in Tests —
        // gibt es keine. Deshalb wird nur dann eine eigene Gruppe geöffnet,
        // wenn tatsächlich keine offen ist: So bleibt das Verhalten im
        // Programm unverändert, und der Store funktioniert trotzdem ohne
        // Ereignisschleife.
        let needsOwnGroup = undoManager.groupingLevel == 0
        if needsOwnGroup { undoManager.beginUndoGrouping() }
        defer { if needsOwnGroup { undoManager.endUndoGrouping() } }

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

    public var selectedNodes: [Node] {
        document.nodes.filter { selection.contains($0.id) }
    }

    public func select(_ id: UUID, extending: Bool) {
        if extending {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    public func selectAll() {
        selection = Set(document.nodes.map(\.id))
    }

    public func clearSelection() {
        selection.removeAll()
    }
}
