import AppKit
import SceauCore

/// Der Verlauf als echte Zeitachse: kräftig bis zum aktuellen Schritt, schwach
/// für den bereits widerrufenen Teil, mit einer senkrechten Marke an der
/// gegenwärtigen Position.
///
/// Bewusst **eine** Zeichenansicht statt mehrerer Unteransichten: Linie, Raster
/// und Marke müssen pixelgenau zusammenpassen, was bei getrennten Ansichten mit
/// Rundung und Layout schnell sichtbare Lücken ergibt.
///
/// Gerechnet wird ausschliesslich mit ``UndoTimelineGeometry`` — dieselbe
/// Rechnung für das Zeichnen und für die Treffer­prüfung, sonst springt ein Zug
/// woanders hin, als die Marke steht.
@MainActor
final class UndoTimelineView: NSView {

    private var undoDepth = 0
    private var redoDepth = 0
    private var pointer = UndoTimelinePointer()

    /// Wird mit der Zieltiefe gerufen — der Anzahl Schritte, die danach noch
    /// widerrufbar sein sollen.
    var onSelectDepth: ((Int) -> Void)?

    private var geometry: UndoTimelineGeometry {
        UndoTimelineGeometry(width: bounds.width, undoDepth: undoDepth, redoDepth: redoDepth)
    }

    /// Klicks kommen auch an, wenn das Fenster noch nicht aktiv ist — die Pille
    /// schwebt über der Zeichenfläche und wird oft im Vorbeigehen benutzt.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setDepths(undo: Int, redo: Int) {
        guard undo != undoDepth || redo != redoDepth else { return }
        undoDepth = max(0, undo)
        redoDepth = max(0, redo)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let geometry = geometry
        let total = geometry.totalDepth
        let markerX = geometry.markerX
        let centerY = bounds.midY

        let weakLine = NSBezierPath()
        weakLine.move(to: NSPoint(x: total == 0 ? geometry.lineMinX : markerX, y: centerY))
        weakLine.line(to: NSPoint(x: geometry.lineMaxX, y: centerY))
        weakLine.lineWidth = 1.5
        NSColor.tertiaryLabelColor.setStroke()
        weakLine.stroke()

        if total > 0 {
            let strongLine = NSBezierPath()
            strongLine.move(to: NSPoint(x: geometry.lineMinX, y: centerY))
            strongLine.line(to: NSPoint(x: markerX, y: centerY))
            strongLine.lineWidth = 1.5
            NSColor.labelColor.setStroke()
            strongLine.stroke()
        }

        // Bei wenigen Schritten zeigt das Raster, dass die Achse aus einzelnen
        // erreichbaren Zuständen besteht. Ab etwa vierzig Positionen liefen die
        // Striche optisch ineinander und machten die Richtung schlechter
        // lesbar — dann bleibt nur die Linie.
        if total > 0, total <= 40 {
            for step in 0...total {
                let x = geometry.x(forStep: step)
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: x, y: centerY - 4.5))
                tick.line(to: NSPoint(x: x, y: centerY + 4.5))
                tick.lineWidth = 2
                (step <= undoDepth ? NSColor.labelColor : NSColor.tertiaryLabelColor).setStroke()
                tick.stroke()
            }
        }

        let marker = NSBezierPath()
        marker.move(to: NSPoint(x: markerX, y: centerY - 9))
        marker.line(to: NSPoint(x: markerX, y: centerY + 9))
        marker.lineWidth = 1.5
        NSColor.labelColor.setStroke()
        marker.stroke()
    }

    // MARK: - Ziehen

    private func handlePointer(at locationInWindow: NSPoint) {
        let x = convert(locationInWindow, from: nil).x
        guard let target = pointer.report(atX: x, geometry: geometry) else { return }
        onSelectDepth?(target)
    }

    override func mouseDown(with event: NSEvent) {
        pointer.begin()
        handlePointer(at: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        handlePointer(at: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        handlePointer(at: event.locationInWindow)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}
