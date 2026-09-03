import CoreGraphics

/// Ein einzelnes kubisches Bézier-Segment zwischen zwei Ankerpunkten.
///
/// Wird aus ``Subpath`` abgeleitet und ist die Einheit, auf der Abflachung
/// (``Flattener``) und Kurvenmathematik arbeiten. Gerade Strecken werden als
/// Segment dargestellt, dessen Kontrollpunkte auf den Endpunkten liegen.
public struct CubicSegment: Equatable, Sendable {
    public var start: CGPoint
    public var control1: CGPoint
    public var control2: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
    }

    /// Gerade Strecke als entartetes kubisches Segment.
    public init(line start: CGPoint, _ end: CGPoint) {
        self.init(start: start, control1: start, control2: end, end: end)
    }

    /// `true`, wenn beide Kontrollpunkte auf ihrem jeweiligen Endpunkt liegen,
    /// das Segment also exakt eine Gerade ist.
    public var isLine: Bool {
        control1 == start && control2 == end
    }

    /// Punkt auf der Kurve bei Parameter `t` (0…1), via De-Casteljau.
    public func point(at t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(
            x: a * start.x + b * control1.x + c * control2.x + d * end.x,
            y: a * start.y + b * control1.y + c * control2.y + d * end.y
        )
    }
}
