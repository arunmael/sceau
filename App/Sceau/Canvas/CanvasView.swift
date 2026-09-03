import AppKit
import SceauCore

/// Die acht Griffpunkte um eine Auswahl.
enum ResizeHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// Position des Griffs auf einem Rahmen.
    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    var cursor: NSCursor {
        switch self {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        default: return .crosshair
        }
    }
}

/// Die Zeichenfläche.
///
/// Bewusst eine eigene `NSView` statt SwiftUI: Ankerpunkte, Griffe, Snapping und
/// Treffergenauigkeit brauchen vollen Zugriff auf die Ereignisbehandlung —
/// genau der Punkt, an dem SwiftUI im Weg wäre.
///
/// Die View ist **umgedreht** (`isFlipped == true`), damit ihre Koordinaten
/// dieselbe Richtung haben wie das Dokumentmodell und SVG: Ursprung links oben,
/// y nach unten. Das ist die einzige Stelle im Programm, die diese Umkehrung
/// vornimmt.
final class CanvasView: NSView {

    private let store: DocumentStore

    /// Enthält Zeichenflächen-Hintergrund und die gerenderten Knoten.
    private let contentLayer = CALayer()
    /// Liegt darüber: Auswahlrahmen, Griffe, Aufziehvorschau.
    private let overlayLayer = CALayer()

    /// Bildschirmposition des Dokumentursprungs (0,0), in View-Koordinaten.
    private var documentOrigin: CGPoint = .zero

    private var interaction: Interaction = .idle

    /// Kantenlänge eines Griffpunkts auf dem Bildschirm.
    ///
    /// Deutlich grösser als die klassischen 6 pt: Die App soll sich laut
    /// Entwicklungsplan auch per Finger über Sidecar bedienen lassen, und dafür
    /// sind kleine Griffe der kritische Punkt.
    private static let handleScreenSize: CGFloat = 11

    /// Was gerade mit der Maus getan wird.
    private enum Interaction {
        case idle
        /// Eine neue Grundform wird aufgezogen.
        case creating(origin: CGPoint, current: CGPoint)
        /// Die Auswahl wird verschoben.
        case moving(start: CGPoint, originals: [UUID: Node])
        /// Ein Griff wird gezogen.
        case resizing(handle: ResizeHandle, startBounds: CGRect, originals: [UUID: Node])
        /// Auswahlrechteck wird aufgezogen.
        case marquee(origin: CGPoint, current: CGPoint)
    }

    init(store: DocumentStore) {
        self.store = store
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Kindebenen sollen dieselbe Achsenrichtung haben wie die umgedrehte
        // View, sonst stünde alles Gezeichnete auf dem Kopf.
        contentLayer.isGeometryFlipped = true
        overlayLayer.isGeometryFlipped = true
        layer?.addSublayer(contentLayer)
        layer?.addSublayer(overlayLayer)

        observeStore()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Nur programmatisch verwendet") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Beobachtung

    /// Zeichnet neu, sobald sich am Store etwas Sichtbares ändert.
    ///
    /// `withObservationTracking` meldet nur **eine** Änderung, deshalb wird die
    /// Beobachtung im Änderungsfall sofort neu aufgesetzt.
    private func observeStore() {
        withObservationTracking {
            _ = store.document
            _ = store.selection
            _ = store.zoom
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                self.observeStore()
            }
        }
    }

    // MARK: - Koordinaten

    var zoom: CGFloat { store.zoom }

    func documentPoint(from viewPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (viewPoint.x - documentOrigin.x) / zoom,
            y: (viewPoint.y - documentOrigin.y) / zoom
        )
    }

    func viewPoint(from documentPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: documentPoint.x * zoom + documentOrigin.x,
            y: documentPoint.y * zoom + documentOrigin.y
        )
    }

    func viewRect(from documentRect: CGRect) -> CGRect {
        CGRect(
            origin: viewPoint(from: documentRect.origin),
            size: CGSize(width: documentRect.width * zoom, height: documentRect.height * zoom)
        )
    }

    /// Zentriert die Zeichenfläche im sichtbaren Bereich.
    func centerArtboard() {
        let size = store.document.artboard.size
        documentOrigin = CGPoint(
            x: (bounds.width - size.width * zoom) / 2,
            y: (bounds.height - size.height * zoom) / 2
        )
        refresh()
    }

    override func layout() {
        super.layout()
        centerArtboard()
    }

    // MARK: - Zeichnen

    func refresh() {
        // Ohne diese Klammer animiert Core Animation jede Pfadänderung nach —
        // beim Ziehen einer Form sähe das aus wie Nachlauf.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        rebuildContent()
        rebuildOverlay()
    }

    private func rebuildContent() {
        contentLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        contentLayer.frame = bounds

        let artboard = store.document.artboard
        let artboardRect = viewRect(from: artboard.frame)

        // Zeichenfläche: heller Grund mit feiner Kontur, damit klar ist, was
        // später exportiert wird und was daneben liegt.
        let background = CALayer()
        background.frame = artboardRect
        background.backgroundColor = artboard.background.alpha > 0
            ? artboard.background.cgColor
            : NSColor.white.cgColor
        background.borderColor = NSColor.separatorColor.cgColor
        background.borderWidth = 1
        background.shadowColor = NSColor.black.cgColor
        background.shadowOpacity = 0.12
        background.shadowRadius = 8
        background.shadowOffset = CGSize(width: 0, height: 2)
        contentLayer.addSublayer(background)

        // Der Inhalt lebt in Dokumentkoordinaten; Zoom und Verschiebung machen
        // eine einzige Transformation auf dem Container, statt jede Form einzeln
        // umzurechnen.
        let nodesLayer = CALayer()
        nodesLayer.frame = bounds
        nodesLayer.transform = CATransform3DConcat(
            CATransform3DMakeScale(zoom, zoom, 1),
            CATransform3DMakeTranslation(documentOrigin.x, documentOrigin.y, 0)
        )
        nodesLayer.anchorPoint = .zero
        nodesLayer.position = .zero
        nodesLayer.masksToBounds = false

        for node in store.document.nodes {
            if let layer = CanvasRenderer.makeLayer(for: node) {
                nodesLayer.addSublayer(layer)
            }
        }
        contentLayer.addSublayer(nodesLayer)
    }

    private func rebuildOverlay() {
        overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        overlayLayer.frame = bounds

        switch interaction {
        case let .creating(origin, current):
            addOutline(rect: CGRect(from: origin, to: current), color: .controlAccentColor, dashed: true)
        case let .marquee(origin, current):
            addOutline(rect: CGRect(from: origin, to: current), color: .controlAccentColor, dashed: true, filled: true)
        default:
            break
        }

        guard !store.selection.isEmpty else { return }

        for node in store.document.nodes where store.selection.contains(node.id) {
            let box = NodeGeometry.bounds(for: node)
            guard !box.isNull else { continue }
            addOutline(rect: viewRect(from: box), color: .controlAccentColor, dashed: false)
        }

        // Griffe nur bei genau einer Auswahl — bei mehreren wäre unklar, worauf
        // sich das Skalieren bezieht.
        if let box = singleSelectionBounds() {
            for handle in ResizeHandle.allCases {
                addHandle(at: handle.position(in: viewRect(from: box)))
            }
        }
    }

    private func addOutline(rect: CGRect, color: NSColor, dashed: Bool, filled: Bool = false) {
        let shape = CAShapeLayer()
        shape.path = CGPath(rect: rect, transform: nil)
        shape.fillColor = filled ? color.withAlphaComponent(0.08).cgColor : nil
        shape.strokeColor = color.cgColor
        shape.lineWidth = 1
        if dashed { shape.lineDashPattern = [4, 3] }
        overlayLayer.addSublayer(shape)
    }

    private func addHandle(at point: CGPoint) {
        let size = Self.handleScreenSize
        let shape = CAShapeLayer()
        shape.path = CGPath(
            ellipseIn: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size),
            transform: nil
        )
        shape.fillColor = NSColor.white.cgColor
        shape.strokeColor = NSColor.controlAccentColor.cgColor
        shape.lineWidth = 1.5
        overlayLayer.addSublayer(shape)
    }

    private func singleSelectionBounds() -> CGRect? {
        guard store.selection.count == 1,
              let id = store.selection.first,
              let node = store.document.nodes.first(where: { $0.id == id })
        else { return nil }
        let box = NodeGeometry.bounds(for: node)
        return box.isNull ? nil : box
    }

    // MARK: - Treffertests

    /// Der oberste Knoten unter einem Dokumentpunkt.
    private func node(at point: CGPoint) -> Node? {
        // Rückwärts, weil der zuletzt gezeichnete Knoten obenauf liegt.
        for node in store.document.nodes.reversed() where node.isVisible && !node.isLocked {
            if hits(node: node, point: point) { return node }
        }
        return nil
    }

    private func hits(node: Node, point: CGPoint) -> Bool {
        let path = NodeGeometry.path(for: node)
        guard !path.isEmpty else { return false }
        let cgPath = path.cgPath

        let rule: CGPathFillRule = node.style.fillRule == .evenOdd ? .evenOdd : .winding
        if node.style.fill != .none, cgPath.contains(point, using: rule) {
            return true
        }
        // Nicht gefüllte Formen müssen über ihre Kontur greifbar bleiben, sonst
        // liesse sich ein reiner Umriss nicht anklicken. Die Trefferbreite ist
        // dabei bewusst grosszügiger als die gezeichnete Linie.
        let strokeWidth = max(node.style.stroke?.width ?? 0, Self.handleScreenSize / zoom)
        let outline = cgPath.copy(strokingWithWidth: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return outline.contains(point)
    }

    private func handle(at viewPoint: CGPoint) -> ResizeHandle? {
        guard let box = singleSelectionBounds() else { return nil }
        let rect = viewRect(from: box)
        let tolerance = Self.handleScreenSize
        for handle in ResizeHandle.allCases {
            let position = handle.position(in: rect)
            if abs(position.x - viewPoint.x) <= tolerance / 2,
               abs(position.y - viewPoint.y) <= tolerance / 2 {
                return handle
            }
        }
        return nil
    }

    // MARK: - Maus

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let docPoint = documentPoint(from: viewPoint)

        if store.activeTool.createsShape {
            interaction = .creating(origin: docPoint, current: docPoint)
            return
        }

        if let handle = handle(at: viewPoint), let box = singleSelectionBounds() {
            interaction = .resizing(handle: handle, startBounds: box, originals: selectionSnapshot())
            return
        }

        if let hit = node(at: docPoint) {
            let extending = event.modifierFlags.contains(.shift)
            if !store.selection.contains(hit.id) || extending {
                store.select(hit.id, extending: extending)
            }
            interaction = .moving(start: docPoint, originals: selectionSnapshot())
        } else {
            if !event.modifierFlags.contains(.shift) { store.clearSelection() }
            interaction = .marquee(origin: docPoint, current: docPoint)
        }
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        let docPoint = documentPoint(from: convert(event.locationInWindow, from: nil))

        switch interaction {
        case let .creating(origin, _):
            interaction = .creating(origin: origin, current: docPoint)
            rebuildOverlayAnimated()

        case let .marquee(origin, _):
            interaction = .marquee(origin: origin, current: docPoint)
            rebuildOverlayAnimated()

        case let .moving(start, originals):
            let delta = CGVector(dx: docPoint.x - start.x, dy: docPoint.y - start.y)
            applyLive { document in
                for (id, original) in originals {
                    guard var node = document.node(id: id) else { continue }
                    node = NodeTransform.moved(original, by: delta)
                    document.replace(node)
                }
            }

        case let .resizing(handle, startBounds, originals):
            let newBounds = startBounds.resized(handle: handle, to: docPoint)
            applyLive { document in
                for (id, original) in originals {
                    guard document.node(id: id) != nil else { continue }
                    document.replace(NodeTransform.resized(original, from: startBounds, to: newBounds))
                }
            }

        case .idle:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let docPoint = documentPoint(from: convert(event.locationInWindow, from: nil))

        switch interaction {
        case let .creating(origin, _):
            createShape(in: CGRect(from: origin, to: docPoint))

        case let .marquee(origin, _):
            selectNodes(in: CGRect(from: origin, to: docPoint), extending: event.modifierFlags.contains(.shift))

        case .moving, .resizing:
            // Der eigentliche Undo-Schritt wird erst hier festgeschrieben, damit
            // eine Zugbewegung genau einen Schritt ergibt und nicht Hunderte.
            commitLive(actionName: isResizing ? "Grösse ändern" : "Bewegen")

        case .idle:
            break
        }

        interaction = .idle
        refresh()
    }

    private var isResizing: Bool {
        if case .resizing = interaction { return true }
        return false
    }

    // MARK: - Änderungen während einer Zugbewegung
    //
    // Während gezogen wird, darf nicht jeder Mausschritt einen eigenen
    // Undo-Eintrag erzeugen. Deshalb wird der Ausgangszustand einmal gemerkt,
    // zwischendurch ohne Undo geschrieben und erst beim Loslassen ein einziger
    // Schritt registriert.

    private var liveBaseline: Document?

    private func applyLive(_ mutate: (inout Document) -> Void) {
        if liveBaseline == nil { liveBaseline = store.document }
        var draft = store.document
        mutate(&draft)
        store.setDocumentWithoutUndo(draft)
        refresh()
    }

    private func commitLive(actionName: String) {
        guard let baseline = liveBaseline else { return }
        let result = store.document
        liveBaseline = nil
        store.setDocumentWithoutUndo(baseline)
        store.apply(actionName) { $0 = result }
    }

    private func selectionSnapshot() -> [UUID: Node] {
        var snapshot: [UUID: Node] = [:]
        for id in store.selection {
            if let node = store.document.node(id: id) { snapshot[id] = node }
        }
        return snapshot
    }

    private func rebuildOverlayAnimated() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rebuildOverlay()
        CATransaction.commit()
    }

    // MARK: - Werkzeugaktionen

    private func createShape(in rect: CGRect) {
        // Ein blosser Klick ohne Zugbewegung soll keine unsichtbare Form
        // hinterlassen.
        guard rect.width >= 1, rect.height >= 1 else { return }

        let spec: ShapeSpec? = switch store.activeTool {
        case .rectangle: .rectangle(frame: rect, cornerRadius: 0)
        case .ellipse: .ellipse(frame: rect)
        case .polygon: .polygon(frame: rect, sides: 5)
        case .star: .star(frame: rect, points: 5, innerRatio: 0.45)
        default: nil
        }
        guard let spec else { return }

        let node = Node(shape: spec)
        store.apply("Form hinzufügen") { $0.appendOnTop(node) }
        store.selection = [node.id]
        store.activeTool = .select
    }

    private func selectNodes(in rect: CGRect, extending: Bool) {
        let hits = store.document.nodes
            .filter { $0.isVisible && !$0.isLocked }
            .filter { rect.intersects(NodeGeometry.bounds(for: $0)) }
            .map(\.id)

        if extending {
            store.selection.formUnion(hits)
        } else {
            store.selection = Set(hits)
        }
    }

    // MARK: - Tastatur

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // Rückschritt und Entfernen
            deleteSelection()
        case 53: // Esc
            store.clearSelection()
            store.activeTool = .select
        default:
            // Werkzeugkürzel nur ohne Befehlstaste, damit sie den Menübefehlen
            // nicht in die Quere kommen.
            guard !event.modifierFlags.contains(.command),
                  let characters = event.charactersIgnoringModifiers?.lowercased(),
                  let tool = Self.toolShortcuts[characters]
            else {
                super.keyDown(with: event)
                return
            }
            store.activeTool = tool
        }
    }

    private static let toolShortcuts: [String: ToolKind] = [
        "v": .select,
        "r": .rectangle,
        "e": .ellipse,
        "y": .polygon,
        "s": .star,
        "p": .pen,
        "t": .text
    ]

    private func deleteSelection() {
        let ids = store.selection
        guard !ids.isEmpty else { return }
        store.apply(ids.count == 1 ? "Objekt löschen" : "Objekte löschen") { document in
            document.remove(ids: ids)
        }
        store.clearSelection()
    }

    override func selectAll(_ sender: Any?) {
        store.selectAll()
    }

    // MARK: - Zoom

    override func magnify(with event: NSEvent) {
        // Pinch-to-Zoom über Trackpad und, per Sidecar, direkt auf dem iPad.
        let factor = 1 + event.magnification
        store.zoom = min(64, max(0.05, store.zoom * factor))
        centerArtboard()
    }

    override func scrollWheel(with event: NSEvent) {
        documentOrigin.x += event.scrollingDeltaX
        documentOrigin.y += event.scrollingDeltaY
        refresh()
    }
}

// MARK: - Hilfen

extension CGRect {
    /// Wendet das Ziehen eines Griffs auf diesen Rahmen an.
    func resized(handle: ResizeHandle, to point: CGPoint) -> CGRect {
        var minX = self.minX, minY = self.minY, maxX = self.maxX, maxY = self.maxY

        switch handle {
        case .topLeft: minX = point.x; minY = point.y
        case .top: minY = point.y
        case .topRight: maxX = point.x; minY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; maxY = point.y
        case .bottom: maxY = point.y
        case .bottomLeft: minX = point.x; maxY = point.y
        case .left: minX = point.x
        }

        return CGRect(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY))
    }
}
