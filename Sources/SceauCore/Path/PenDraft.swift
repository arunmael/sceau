import CoreGraphics

/// Der noch nicht abgeschlossene Pfad, an dem der Zeichenstift gerade arbeitet.
///
/// Bewusst ein Werttyp im Kern statt Zustand in der Zeichenfläche: Die
/// eigentliche Feinheit des Werkzeugs steckt in der Griff-Semantik, und die
/// lässt sich hier ohne laufende Oberfläche prüfen.
public struct PenDraft: Equatable, Sendable {
    public private(set) var anchors: [Anchor] = []

    public init() {}

    public var isEmpty: Bool { anchors.isEmpty }

    /// Setzt einen neuen Ankerpunkt.
    ///
    /// Zunächst als Eckpunkt — erst wenn der Nutzer bei gedrückter Maustaste
    /// zieht, wird über ``dragHandleOfLastAnchor(to:)`` eine Kurve daraus. Das
    /// entspricht dem Verhalten, das man von Zeichenstiften kennt: klicken
    /// ergibt Ecken, ziehen ergibt Rundungen.
    public mutating func addAnchor(at point: CGPoint) {
        anchors.append(Anchor(corner: point))
    }

    /// Zieht den ausgehenden Griff des zuletzt gesetzten Ankers.
    ///
    /// Der eingehende Griff wird dabei am Anker gespiegelt, sodass die Kurve
    /// glatt durch den Punkt läuft.
    public mutating func dragHandleOfLastAnchor(to point: CGPoint) {
        guard var last = anchors.last else { return }
        last.controlOut = point
        last.controlIn = CGPoint(
            x: 2 * last.point.x - point.x,
            y: 2 * last.point.y - point.y
        )
        last.style = .symmetric
        anchors[anchors.count - 1] = last
    }

    /// Nimmt den zuletzt gesetzten Anker zurück.
    public mutating func removeLastAnchor() {
        guard !anchors.isEmpty else { return }
        anchors.removeLast()
    }

    /// Ob ein Punkt auf dem ersten Anker liegt und der Pfad damit geschlossen
    /// werden kann.
    ///
    /// Mit weniger als zwei Ankern gibt es nichts zu schliessen — sonst würde
    /// ein Doppelklick beim Setzen des ersten Punktes sofort einen leeren Pfad
    /// erzeugen.
    public func isOverFirstAnchor(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        guard anchors.count >= 2, let first = anchors.first else { return false }
        return hypot(first.point.x - point.x, first.point.y - point.y) <= tolerance
    }

    /// Der fertige Pfad, oder `nil`, wenn zu wenige Anker gesetzt wurden.
    public func path(closed: Bool) -> VectorPath? {
        guard anchors.count >= 2 else { return nil }
        return VectorPath(subpath: Subpath(anchors: anchors, isClosed: closed))
    }

    /// Die Vorschau während des Zeichnens, wahlweise mit einem Segment zur
    /// aktuellen Mausposition.
    public func previewPath(cursor: CGPoint?) -> VectorPath {
        var preview = anchors
        if let cursor {
            preview.append(Anchor(corner: cursor))
        }
        guard !preview.isEmpty else { return VectorPath() }
        return VectorPath(subpath: Subpath(anchors: preview, isClosed: false))
    }
}
