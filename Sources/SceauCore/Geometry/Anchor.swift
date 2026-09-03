import CoreGraphics

/// Wie sich die beiden Kurvengriffe eines Ankerpunkts zueinander verhalten,
/// wenn einer von ihnen bewegt wird.
///
/// Das ist reine Editier-Semantik — die Geometrie selbst steckt ausschliesslich
/// in den absoluten Koordinaten von ``Anchor/controlIn`` und ``Anchor/controlOut``.
public enum AnchorStyle: String, Codable, Sendable, CaseIterable {
    /// Griffe sind voneinander unabhängig (harte Ecke).
    case corner
    /// Griffe bleiben kollinear, ihre Längen sind unabhängig.
    case smooth
    /// Griffe bleiben kollinear und gleich lang.
    case symmetric
}

/// Ein Ankerpunkt eines Pfades samt seinen beiden Kurvengriffen.
///
/// Beide Griffe werden in **absoluten** Koordinaten gehalten (nicht als Offset zum
/// Anker) — das entspricht der SVG-Sicht und erspart beim Rendern pro Frame eine
/// Umrechnung. Beim Verschieben des Ankers müssen die Griffe entsprechend
/// mitgeführt werden; dafür gibt es ``moved(by:)``.
///
/// Ein Anker ohne Kurvenwirkung ("Eckpunkt") wird dadurch ausgedrückt, dass ein
/// Griff auf dem Anker selbst liegt — es gibt bewusst keine Optionals, damit jede
/// Pfadstelle einheitlich behandelt werden kann.
public struct Anchor: Equatable, Sendable, Codable {
    /// Position des Ankerpunkts.
    public var point: CGPoint
    /// Griff in Richtung des *vorhergehenden* Segments, absolut.
    public var controlIn: CGPoint
    /// Griff in Richtung des *nachfolgenden* Segments, absolut.
    public var controlOut: CGPoint
    /// Editier-Semantik der beiden Griffe.
    public var style: AnchorStyle

    public init(
        point: CGPoint,
        controlIn: CGPoint,
        controlOut: CGPoint,
        style: AnchorStyle = .corner
    ) {
        self.point = point
        self.controlIn = controlIn
        self.controlOut = controlOut
        self.style = style
    }

    /// Erzeugt einen Eckpunkt: beide Griffe liegen auf dem Anker, es entstehen
    /// also gerade Segmente zu den Nachbarn.
    public init(corner point: CGPoint) {
        self.init(point: point, controlIn: point, controlOut: point, style: .corner)
    }

    /// `true`, wenn der eingehende Griff keine Kurvenwirkung hat.
    public var hasStraightIn: Bool { controlIn == point }

    /// `true`, wenn der ausgehende Griff keine Kurvenwirkung hat.
    public var hasStraightOut: Bool { controlOut == point }

    /// Verschiebt Anker und beide Griffe gemeinsam.
    public func moved(by delta: CGVector) -> Anchor {
        Anchor(
            point: CGPoint(x: point.x + delta.dx, y: point.y + delta.dy),
            controlIn: CGPoint(x: controlIn.x + delta.dx, y: controlIn.y + delta.dy),
            controlOut: CGPoint(x: controlOut.x + delta.dx, y: controlOut.y + delta.dy),
            style: style
        )
    }
}
