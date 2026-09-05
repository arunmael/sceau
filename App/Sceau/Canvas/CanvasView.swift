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

    /// Der Griff auf der gegenüberliegenden Seite — der Punkt, der beim
    /// proportionalen Ziehen als Anker fix bleiben muss.
    var opposite: ResizeHandle {
        switch self {
        case .topLeft: return .bottomRight
        case .top: return .bottom
        case .topRight: return .bottomLeft
        case .right: return .left
        case .bottomRight: return .topLeft
        case .bottom: return .top
        case .bottomLeft: return .topRight
        case .left: return .right
        }
    }

    /// `true` für die vier Eckgriffe. Nur dort ist ein Seitenverhältnis
    /// überhaupt sinnvoll sperrbar — ein Kantengriff verändert per Definition
    /// nur eine Achse.
    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: return true
        case .top, .right, .bottom, .left: return false
        }
    }

    /// Der Zeiger über diesem Griff.
    ///
    /// AppKit kennt öffentlich nur waagrechte und senkrechte Zug-Cursor, keinen
    /// diagonalen — private API dafür wäre nicht zukunftssicher. Eckgriffe
    /// bekommen deshalb das Fadenkreuz, das auch beim Formen-Aufziehen benutzt
    /// wird: eindeutig "hier wird gezogen", ohne eine falsche Richtung zu suggerieren.
    var resizeCursor: NSCursor {
        switch self {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        case .topLeft, .topRight, .bottomRight, .bottomLeft: return .crosshair
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
final class CanvasView: NSView, NSUserInterfaceValidations {

    private let store: DocumentStore

    /// Enthält Zeichenflächen-Hintergrund und die gerenderten Knoten.
    private let contentLayer = CALayer()
    /// Liegt darüber: Auswahlrahmen, Griffe, Aufziehvorschau.
    private let overlayLayer = CALayer()

    /// Bildschirmposition des Dokumentursprungs (0,0), in View-Koordinaten.
    private var documentOrigin: CGPoint = .zero

    private var interaction: Interaction = .idle

    /// Der Pfad, an dem der Zeichenstift gerade arbeitet.
    private var penDraft = PenDraft()

    /// Letzte bekannte Mausposition in Dokumentkoordinaten — für die
    /// Gummiband-Vorschau des Zeichenstifts.
    private var cursorPoint: CGPoint?

    private var mouseTracking: NSTrackingArea?

    /// Hilfslinien der aktuell wirksamen Einrastungen.
    private var activeGuides: [SnapGuide] = []

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
        /// Eine Ecke wird frei verzogen (Werkzeug "Verzerren").
        case distorting(corner: ResizeHandle, startBounds: CGRect, originals: [UUID: Node])
        /// Auswahlrechteck wird aufgezogen.
        case marquee(origin: CGPoint, current: CGPoint)
        /// Am Griff des soeben gesetzten Ankers wird gezogen.
        case penHandle
        /// Ein Anker oder Griff eines bestehenden Pfades wird bewegt.
        case editingAnchor(node: UUID, address: AnchorAddress, handle: AnchorHandle)
    }

    init(store: DocumentStore) {
        self.store = store
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Bewusst **kein** `isGeometryFlipped` auf diesen Ebenen: AppKit dreht
        // die Trägerebene einer umgedrehten View bereits selbst, sodass
        // Kindebenen schon in Dokumentrichtung liegen (Ursprung links oben).
        // Es zusätzlich zu setzen kehrt die Achse ein zweites Mal um und
        // stellt den gesamten Inhalt auf den Kopf.
        layer?.addSublayer(contentLayer)
        layer?.addSublayer(overlayLayer)

        observeStore()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Nur programmatisch verwendet") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Bedienungshilfen
    //
    // Ohne diese Angaben ist die Zeichenfläche für die Bedienungshilfen eine
    // namenlose Fläche — sie taucht weder in der Vorlesereihenfolge auf noch
    // lässt sich von aussen feststellen, ob sie den Tastaturfokus hat.

    override func accessibilityRole() -> NSAccessibility.Role? {
        .layoutArea
    }

    override func accessibilityLabel() -> String? {
        "Zeichenfläche"
    }

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
            _ = store.activeTool
            _ = store.showsGrid
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

    /// Hält die gesamte Zeichenfläche sichtbar, damit nach dem Einpassen kein
    /// zusätzlicher Bildlauf nötig ist.
    func zoomToFitArtboard() {
        store.zoom = ViewFitting.zoomToFit(
            artboard: store.document.artboard.size,
            in: bounds.size
        )
        centerArtboard()
    }

    /// Ändert den Zoom so, dass der Punkt unter `viewAnchor` stehen bleibt.
    ///
    /// Ohne diesen Bezugspunkt wandert beim Zoomen die Stelle weg, die man
    /// gerade betrachtet — man zoomt an seiner Arbeit vorbei.
    func setZoom(_ newValue: CGFloat, keeping viewAnchor: CGPoint) {
        let clamped = min(64, max(0.05, newValue))
        guard clamped != zoom else { return }

        let anchorInDocument = documentPoint(from: viewAnchor)
        store.zoom = clamped
        documentOrigin = CGPoint(
            x: viewAnchor.x - anchorInDocument.x * clamped,
            y: viewAnchor.y - anchorInDocument.y * clamped
        )
        refresh()
    }

    /// Zoomt um die Mitte der Ansicht — der Bezugspunkt für Menübefehle, bei
    /// denen es keine Mausposition gibt.
    func setZoomAroundCenter(_ newValue: CGFloat) {
        setZoom(newValue, keeping: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    /// Wurde die Zeichenfläche schon einmal eingemittet?
    ///
    /// Nur beim ersten Mal: Später würde jeder Layout-Durchlauf — also schon
    /// das Ändern der Fenstergrösse — die verschobene Ansicht zurücksetzen.
    private var hasCenteredOnce = false

    override func layout() {
        super.layout()

        if !hasCenteredOnce, bounds.width > 0, bounds.height > 0 {
            hasCenteredOnce = true
            centerArtboard()
        } else {
            refresh()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTracking { removeTrackingArea(mouseTracking) }

        // Nötig für die Gummiband-Vorschau des Zeichenstifts: Ohne verfolgte
        // Mausbewegung wüsste die Vorschau nicht, wohin das nächste Segment
        // laufen soll.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        mouseTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard !penDraft.isEmpty else { return }
        cursorPoint = documentPoint(from: convert(event.locationInWindow, from: nil))
        rebuildOverlayAnimated()
    }

    override func mouseExited(with event: NSEvent) {
        guard cursorPoint != nil else { return }
        cursorPoint = nil
        rebuildOverlayAnimated()
    }

    // MARK: - Zeichnen

    /// Der Mauszeiger sagt, was ein Klick gerade bewirkt.
    ///
    /// Ohne diese Rückmeldung ist bei einem Werkzeugwechsel nicht erkennbar,
    /// ob der nächste Klick auswählt oder zeichnet.
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor(for: store.activeTool))

        // Über den Skaliergriffen zeigt der Zeiger die Zugrichtung — ohne das
        // wirkt ein Griff wie ein normaler Klickpunkt, nicht wie etwas, das
        // sich ziehen lässt. Diese Rechtecke werden nach dem Vollflächen-Rect
        // gesetzt, AppKit bevorzugt bei Überlappung das zuletzt gesetzte.
        guard store.activeTool == .select || store.activeTool == .distort,
              let box = singleSelectionBounds()
        else { return }
        let viewBox = viewRect(from: box)
        // Deckungsgleich mit der Trefferzone in `handle(at:)` — dort ist
        // `handleScreenSize` bereits die volle Kantenlänge, `/2` der Radius.
        let half = Self.handleScreenSize / 2
        let handles = store.activeTool == .distort ? ResizeHandle.allCases.filter(\.isCorner) : ResizeHandle.allCases
        for handle in handles {
            let center = handle.position(in: viewBox)
            let rect = CGRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2)
            addCursorRect(rect, cursor: handle.resizeCursor)
        }
    }

    private func cursor(for tool: ToolKind) -> NSCursor {
        switch tool {
        case .select: return .arrow
        case .rectangle, .ellipse, .polygon, .star, .squircle, .pen: return .crosshair
        case .distort: return .arrow
        case .text: return .iBeam
        }
    }

    func refresh() {
        // Ohne diese Klammer animiert Core Animation jede Pfadänderung nach —
        // beim Ziehen einer Form sähe das aus wie Nachlauf.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        rebuildContent()
        rebuildOverlay()
        window?.invalidateCursorRects(for: self)
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

        if store.showsGrid, let grid = makeGridLayer(in: artboardRect) {
            contentLayer.addSublayer(grid)
        }

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

    /// Zeichnet das Raster innerhalb der Zeichenfläche.
    ///
    /// Nur dort, nicht über die ganze Ansicht: Das Raster ist eine Eigenschaft
    /// des Dokuments, und ausserhalb der Zeichenfläche gibt es nichts
    /// auszurichten.
    private func makeGridLayer(in artboardRect: CGRect) -> CALayer? {
        let spacing = store.gridSize * zoom
        // Bei zu dichten Linien wäre das Raster nur noch eine graue Fläche.
        guard spacing >= 4 else { return nil }

        let path = CGMutablePath()
        var x = artboardRect.minX
        while x <= artboardRect.maxX {
            path.move(to: CGPoint(x: x, y: artboardRect.minY))
            path.addLine(to: CGPoint(x: x, y: artboardRect.maxY))
            x += spacing
        }
        var y = artboardRect.minY
        while y <= artboardRect.maxY {
            path.move(to: CGPoint(x: artboardRect.minX, y: y))
            path.addLine(to: CGPoint(x: artboardRect.maxX, y: y))
            y += spacing
        }

        let layer = CAShapeLayer()
        layer.path = path
        layer.strokeColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        layer.lineWidth = 1 / max(1, backingScaleFactor)
        layer.fillColor = nil
        return layer
    }

    private var backingScaleFactor: CGFloat {
        window?.backingScaleFactor ?? 2
    }

    private func rebuildOverlay() {
        overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        overlayLayer.frame = bounds

        // Beide Eckpunkte liegen in Dokumentkoordinaten, `addOutline` zeichnet
        // dagegen in View-Koordinaten — ohne die Umrechnung sässe die Vorschau
        // um den Betrag des Dokumentursprungs daneben.
        switch interaction {
        case let .creating(origin, current):
            addOutline(
                rect: viewRect(from: CGRect(from: origin, to: current)),
                color: .controlAccentColor,
                dashed: true
            )
        case let .marquee(origin, current):
            addOutline(
                rect: viewRect(from: CGRect(from: origin, to: current)),
                color: .controlAccentColor,
                dashed: true,
                filled: true
            )
        default:
            break
        }

        for guide in activeGuides {
            addGuide(guide)
        }

        // Zeichenstift in Arbeit: Gummiband zur Maus und die bereits gesetzten Anker.
        if !penDraft.isEmpty {
            addStroke(penDraft.previewPath(cursor: cursorPoint), color: .controlAccentColor, dashed: true)
            for (index, anchor) in penDraft.anchors.enumerated() {
                // Der erste Anker ist hervorgehoben, weil ein Klick darauf den
                // Pfad schliesst.
                addAnchorMarker(at: viewPoint(from: anchor.point), emphasized: index == 0)
            }
        }

        guard !store.selection.isEmpty else { return }

        for node in store.document.nodes(with: store.selection) {
            let box = NodeGeometry.bounds(for: node)
            guard !box.isNull else { continue }
            addOutline(rect: viewRect(from: box), color: .controlAccentColor, dashed: false)
        }

        // Mit dem Zeichenstift werden Anker bearbeitet, nicht skaliert — die
        // Skaliergriffe würden dabei nur im Weg liegen.
        if store.activeTool == .pen {
            if penDraft.isEmpty, let path = selectedEditablePath() {
                addAnchorHandles(of: path)
            }
            return
        }

        // Griffe nur bei genau einer Auswahl — bei mehreren wäre unklar, worauf
        // sich das Skalieren bezieht.
        guard let box = singleSelectionBounds() else { return }
        let handles = store.activeTool == .distort
            ? ResizeHandle.allCases.filter(\.isCorner)
            : ResizeHandle.allCases
        for handle in handles {
            addHandle(at: handle.position(in: viewRect(from: box)))
        }
    }

    /// Der Pfad des ausgewählten Knotens, sofern genau einer ausgewählt ist und
    /// er überhaupt Anker hat.
    private func selectedEditablePath() -> VectorPath? {
        guard store.selection.count == 1,
              let id = store.selection.first,
              let node = store.document.node(id: id),
              case let .path(path) = node.content
        else { return nil }
        return path
    }

    /// Zeichnet Anker und Kurvengriffe eines Pfades zum Bearbeiten.
    private func addAnchorHandles(of path: VectorPath) {
        for subpath in path.subpaths {
            for anchor in subpath.anchors {
                let anchorPoint = viewPoint(from: anchor.point)

                for control in [anchor.controlIn, anchor.controlOut] where control != anchor.point {
                    let controlPoint = viewPoint(from: control)
                    addLine(from: anchorPoint, to: controlPoint)
                    addAnchorMarker(at: controlPoint, emphasized: false, round: true)
                }
                addAnchorMarker(at: anchorPoint, emphasized: false)
            }
        }
    }

    /// Zeichnet eine Einrast-Hilfslinie.
    private func addGuide(_ guide: SnapGuide) {
        let path = CGMutablePath()
        switch guide.orientation {
        case .vertical:
            let x = viewPoint(from: CGPoint(x: guide.position, y: 0)).x
            path.move(to: CGPoint(x: x, y: viewPoint(from: CGPoint(x: 0, y: guide.start)).y))
            path.addLine(to: CGPoint(x: x, y: viewPoint(from: CGPoint(x: 0, y: guide.end)).y))
        case .horizontal:
            let y = viewPoint(from: CGPoint(x: 0, y: guide.position)).y
            path.move(to: CGPoint(x: viewPoint(from: CGPoint(x: guide.start, y: 0)).x, y: y))
            path.addLine(to: CGPoint(x: viewPoint(from: CGPoint(x: guide.end, y: 0)).x, y: y))
        }

        let shape = CAShapeLayer()
        shape.path = path
        shape.strokeColor = NSColor.systemPink.cgColor
        shape.lineWidth = 1
        shape.fillColor = nil
        overlayLayer.addSublayer(shape)
    }

    private func addStroke(_ path: VectorPath, color: NSColor, dashed: Bool) {
        guard !path.isEmpty else { return }
        var transform = CGAffineTransform(translationX: documentOrigin.x, y: documentOrigin.y)
            .scaledBy(x: zoom, y: zoom)
        guard let scaled = path.cgPath.copy(using: &transform) else { return }

        let shape = CAShapeLayer()
        shape.path = scaled
        shape.fillColor = nil
        shape.strokeColor = color.cgColor
        shape.lineWidth = 1
        if dashed { shape.lineDashPattern = [4, 3] }
        overlayLayer.addSublayer(shape)
    }

    private func addLine(from: CGPoint, to: CGPoint) {
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)

        let shape = CAShapeLayer()
        shape.path = path
        shape.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        shape.lineWidth = 1
        shape.fillColor = nil
        overlayLayer.addSublayer(shape)
    }

    /// Quadrat für Ankerpunkte, Kreis für Kurvengriffe — dieselbe Unterscheidung
    /// wie in gängigen Vektorprogrammen.
    private func addAnchorMarker(at point: CGPoint, emphasized: Bool, round: Bool = false) {
        let size = Self.handleScreenSize * (emphasized ? 1.0 : 0.75)
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)

        let shape = CAShapeLayer()
        shape.path = round ? CGPath(ellipseIn: rect, transform: nil) : CGPath(rect: rect, transform: nil)
        shape.fillColor = emphasized ? NSColor.controlAccentColor.cgColor : NSColor.white.cgColor
        shape.strokeColor = NSColor.controlAccentColor.cgColor
        shape.lineWidth = 1.5
        overlayLayer.addSublayer(shape)
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
              let node = store.document.node(id: id)
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

        if store.activeTool == .pen {
            // Wahltaste entfernt statt einzufügen — dieselbe Belegung wie in
            // gängigen Vektorprogrammen.
            handlePenMouseDown(at: docPoint, removing: event.modifierFlags.contains(.option))
            return
        }

        if store.activeTool == .text {
            createTextNode(at: docPoint)
            return
        }

        if store.activeTool.createsShape {
            interaction = .creating(origin: docPoint, current: docPoint)
            return
        }

        if store.activeTool == .distort,
           let handle = handle(at: viewPoint), handle.isCorner,
           let box = singleSelectionBounds() {
            interaction = .distorting(corner: handle, startBounds: box, originals: selectionSnapshot())
            return
        }

        // Skaliergriffe gehören dem Auswählen-Werkzeug — im Verzerren-Werkzeug
        // sollen dieselben Eckpunkte stattdessen frei verzogen werden (oben).
        if store.activeTool == .select, let handle = handle(at: viewPoint), let box = singleSelectionBounds() {
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
            var corner = docPoint
            if let settings = snapSettings(event) {
                let snap = Snapper.snap(
                    point: docPoint,
                    to: snapTargets(excluding: []),
                    within: store.document.artboard.frame,
                    settings: settings
                )
                corner = CGPoint(x: docPoint.x + snap.offset.dx, y: docPoint.y + snap.offset.dy)
                activeGuides = snap.guides
            } else {
                activeGuides = []
            }
            interaction = .creating(origin: origin, current: corner)
            rebuildOverlayAnimated()

        case let .marquee(origin, _):
            interaction = .marquee(origin: origin, current: docPoint)
            rebuildOverlayAnimated()

        case let .moving(start, originals):
            var delta = CGVector(dx: docPoint.x - start.x, dy: docPoint.y - start.y)

            // Eingerastet wird der gemeinsame Hüllrahmen der Auswahl, nicht
            // jedes Objekt für sich — sonst zerrisse eine Mehrfachauswahl.
            if let settings = snapSettings(event) {
                let movedBox = LayoutOps
                    .boundingBox(of: originals.values.map { NodeGeometry.bounds(for: $0) })
                    .offsetBy(dx: delta.dx, dy: delta.dy)
                let snap = Snapper.snap(
                    rect: movedBox,
                    to: snapTargets(excluding: Set(originals.keys)),
                    within: store.document.artboard.frame,
                    settings: settings
                )
                delta.dx += snap.offset.dx
                delta.dy += snap.offset.dy
                activeGuides = snap.guides
            } else {
                activeGuides = []
            }

            applyLive { document in
                for (id, original) in originals {
                    guard var node = document.node(id: id) else { continue }
                    node = NodeTransform.moved(original, by: delta)
                    document.replace(node)
                }
            }

        case let .resizing(handle, startBounds, originals):
            var newBounds = startBounds.resized(handle: handle, to: docPoint)
            // Option-Taste sperrt das Seitenverhältnis — nur an Eckgriffen
            // sinnvoll, ein Kantengriff verändert ohnehin nur eine Achse.
            if event.modifierFlags.contains(.option), handle.isCorner,
               startBounds.width > 0, startBounds.height > 0 {
                let anchor = handle.opposite.position(in: startBounds)
                newBounds = ProportionalResize.lockedRect(
                    anchor: anchor,
                    dragPoint: docPoint,
                    aspectRatio: startBounds.width / startBounds.height
                )
            }
            applyLive { document in
                for (id, original) in originals {
                    guard document.node(id: id) != nil else { continue }
                    document.replace(NodeTransform.resized(original, from: startBounds, to: newBounds))
                }
            }

        case let .distorting(corner, startBounds, originals):
            var targetCorners = QuadCorners(rect: startBounds)
            switch corner {
            case .topLeft: targetCorners.topLeft = docPoint
            case .topRight: targetCorners.topRight = docPoint
            case .bottomRight: targetCorners.bottomRight = docPoint
            case .bottomLeft: targetCorners.bottomLeft = docPoint
            case .top, .right, .bottom, .left:
                // Der Hit-Test lässt hier nur Eckgriffe zu (siehe mouseDown).
                break
            }
            applyLive { document in
                for (id, original) in originals {
                    guard document.node(id: id) != nil else { continue }
                    document.replace(NodeTransform.distorted(original, from: startBounds, to: targetCorners))
                }
            }

        case .penHandle:
            penDraft.dragHandleOfLastAnchor(to: docPoint)
            rebuildOverlayAnimated()

        case let .editingAnchor(nodeID, address, handle):
            applyLive { document in
                guard let node = document.node(id: nodeID),
                      case let .path(path) = node.content
                else { return }
                var updated = node
                updated.content = .path(path.movingHandle(handle, at: address, to: docPoint))
                document.replace(updated)
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

        case .moving, .resizing, .distorting:
            // Der eigentliche Undo-Schritt wird erst hier festgeschrieben, damit
            // eine Zugbewegung genau einen Schritt ergibt und nicht Hunderte.
            commitLive(actionName: liveActionName)

        case .editingAnchor:
            commitLive(actionName: "Ankerpunkt bewegen")

        case .penHandle:
            // Der Zeichenstift bleibt aktiv: Loslassen beendet nur das Ziehen
            // am Griff, nicht den Pfad.
            break

        case .idle:
            break
        }

        interaction = .idle
        activeGuides = []
        refresh()
    }

    private var liveActionName: String {
        switch interaction {
        case .resizing: return "Grösse ändern"
        case .distorting: return "Verzerren"
        default: return "Bewegen"
        }
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

    // MARK: - Einrasten

    /// Die Einstellungen für den laufenden Zug, oder `nil`, wenn gerade gar
    /// nicht eingerastet werden soll.
    ///
    /// Die Befehlstaste schaltet das Einrasten vorübergehend ab — der übliche
    /// Weg, um einmal ganz bewusst *nicht* auszurichten. Das wird hier als
    /// „überhaupt nicht einrasten" behandelt statt über die Schalter in
    /// ``SnapSettings``: Die Zeichenfläche bleibt dort bewusst immer ein Ziel,
    /// und genau die soll bei gedrückter Befehlstaste ebenfalls nicht fangen.
    private func snapSettings(_ event: NSEvent) -> SnapSettings? {
        guard store.snapsEnabled, !event.modifierFlags.contains(.command) else { return nil }

        var settings = SnapSettings()
        settings.gridSize = store.showsGrid ? store.gridSize : nil
        // Die Fangweite gilt in Dokumentpunkten; ohne Umrechnung würde sie
        // beim Hineinzoomen unbrauchbar gross.
        settings.threshold /= zoom
        return settings
    }

    /// Die Rahmen, an denen eingerastet werden kann — alles ausser den gerade
    /// bewegten Objekten, denn an sich selbst rastet nichts ein.
    private func snapTargets(excluding excluded: Set<UUID>) -> [CGRect] {
        store.document.nodes
            .filter { $0.isVisible && !excluded.contains($0.id) }
            .map { NodeGeometry.bounds(for: $0) }
            .filter { !$0.isNull }
    }

    // MARK: - Zeichenstift

    /// Trefferradius für Anker und Griffe, umgerechnet in Dokumentpunkte —
    /// beim Hineinzoomen soll die Fangweite auf dem Bildschirm gleich bleiben.
    private var anchorTolerance: CGFloat {
        Self.handleScreenSize / zoom
    }

    private func handlePenMouseDown(at point: CGPoint, removing: Bool) {
        // Bei einem bereits ausgewählten Pfad greift der Zeichenstift dessen
        // Anker und Griffe ab — das ist die Nachbearbeitung aus Abschnitt 5.2
        // des Entwicklungsplans.
        if penDraft.isEmpty,
           let nodeID = store.selection.first,
           store.selection.count == 1,
           let node = store.document.node(id: nodeID),
           case let .path(path) = node.content {

            if let hit = path.hitTestAnchor(at: point, tolerance: anchorTolerance) {
                if removing, hit.handle == .point {
                    removeAnchor(at: hit.address, of: nodeID, in: path)
                } else {
                    interaction = .editingAnchor(node: nodeID, address: hit.address, handle: hit.handle)
                }
                return
            }

            // Kein Anker getroffen, aber die Kontur — dann wird dort einer
            // eingefügt, ohne die Form zu verändern.
            if !removing, let segment = path.closestSegment(to: point, tolerance: anchorTolerance) {
                insertAnchor(at: segment.address, t: segment.t, of: nodeID, in: path)
                return
            }
        }

        // Zurück auf den Anfangspunkt schliesst den Pfad.
        if penDraft.isOverFirstAnchor(point, tolerance: anchorTolerance) {
            finishPenPath(closed: true)
            return
        }

        penDraft.addAnchor(at: point)
        interaction = .penHandle
        rebuildOverlayAnimated()
    }

    private func insertAnchor(at address: AnchorAddress, t: CGFloat, of nodeID: UUID, in path: VectorPath) {
        let expanded = path.insertingAnchor(at: address, t: t)
        store.apply("Ankerpunkt einfügen") { document in
            guard var node = document.node(id: nodeID) else { return }
            node.content = .path(expanded)
            document.replace(node)
        }

        // Direkt weiterziehen können, ohne noch einmal zielen zu müssen.
        interaction = .editingAnchor(
            node: nodeID,
            address: AnchorAddress(subpath: address.subpath, index: address.index + 1),
            handle: .point
        )
    }

    private func removeAnchor(at address: AnchorAddress, of nodeID: UUID, in path: VectorPath) {
        let reduced = path.removingAnchor(at: address)
        guard reduced != path else { return }

        store.apply("Ankerpunkt entfernen") { document in
            guard var node = document.node(id: nodeID) else { return }
            node.content = .path(reduced)
            document.replace(node)
        }
    }

    /// Schliesst den gezeichneten Pfad ab und legt ihn als Knoten an.
    private func finishPenPath(closed: Bool) {
        defer {
            penDraft = PenDraft()
            interaction = .idle
            refresh()
        }

        guard let path = penDraft.path(closed: closed) else { return }

        // Ein offener Pfad ohne Kontur wäre unsichtbar — deshalb bekommt er
        // eine, während eine geschlossene Form gefüllt wird.
        var style = Style()
        if !closed {
            style.fill = .none
            style.stroke = Stroke(paint: .solid(.black), width: 2, cap: .round, join: .round)
        }

        let node = Node(name: closed ? "Pfad" : "Linie", style: style, content: .path(path))
        store.apply("Pfad zeichnen") { $0.appendOnTop(node) }
        store.selection = [node.id]
    }

    private func cancelPenPath() {
        penDraft = PenDraft()
        interaction = .idle
        refresh()
    }

    // MARK: - Text

    private func createTextNode(at point: CGPoint) {
        let node = Node(
            name: "Text",
            style: Style(fill: .solid(.black)),
            content: .text(TextSpec(string: "Text", origin: point))
        )
        store.apply("Text hinzufügen") { $0.appendOnTop(node) }
        store.selection = [node.id]
        // Weiter geht es im Inspektor; das Werkzeug hat seine Aufgabe erfüllt.
        store.activeTool = .select
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
        case .squircle: .squircle(frame: rect)
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
        // Solange gezeichnet wird, gehören diese Tasten dem Zeichenstift.
        if !penDraft.isEmpty {
            switch event.keyCode {
            case 36, 76: // Zeilenschalter und Enter
                finishPenPath(closed: false)
                return
            case 53: // Esc
                cancelPenPath()
                return
            case 51, 117: // Rückschritt und Entfernen
                penDraft.removeLastAnchor()
                rebuildOverlayAnimated()
                return
            default:
                break
            }
        }

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

    // MARK: - Bearbeiten-Menü
    //
    // Diese Befehle laufen über die Responder-Kette. Liegt der Tastaturfokus
    // dagegen in einem Textfeld der Paletten, greifen dort die üblichen
    // Textbefehle — genau wie erwartet.

    @objc func copy(_ sender: Any?) {
        ClipboardCommands.copy(from: store)
    }

    @objc func cut(_ sender: Any?) {
        ClipboardCommands.cut(from: store)
    }

    @objc func paste(_ sender: Any?) {
        ClipboardCommands.paste(into: store)
    }

    @objc func duplicate(_ sender: Any?) {
        ClipboardCommands.duplicate(in: store)
    }

    @objc func delete(_ sender: Any?) {
        deleteSelection()
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)), #selector(duplicate(_:)):
            return !store.selection.isEmpty
        case #selector(paste(_:)):
            return ClipboardCommands.canPaste()
        case #selector(selectAll(_:)):
            return !store.document.nodes.isEmpty
        default:
            // Alles Übrige entscheidet die Responder-Kette weiter oben.
            return true
        }
    }

    // MARK: - Zoom

    override func magnify(with event: NSEvent) {
        // Pinch-to-Zoom über Trackpad und, per Sidecar, direkt auf dem iPad.
        // Bezugspunkt sind die Finger, nicht die Mitte der Ansicht.
        let anchor = convert(event.locationInWindow, from: nil)
        setZoom(zoom * (1 + event.magnification), keeping: anchor)
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
