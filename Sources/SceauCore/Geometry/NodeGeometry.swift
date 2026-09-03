import CoreGraphics

/// Löst einen Dokumentknoten (``Node``) in seine tatsächliche Kontur in
/// Dokumentkoordinaten auf, inklusive Rotation.
///
/// Getrennt von ``ShapeGeometry``, weil ein Knoten mehr Kontext mitbringt als
/// eine reine Grundform: Gruppen müssen ihre Kinder vereinigen, und die
/// Rotation (die auf ``Node``, nicht auf ``ShapeSpec`` sitzt) muss angewandt
/// werden, bevor Bounds oder Rendering sinnvoll sind.
public enum NodeGeometry {

    /// Die aufgelöste Kontur eines Knotens in Dokumentkoordinaten, inklusive Rotation.
    public static func path(for node: Node) -> VectorPath {
        let unrotated = unrotatedPath(for: node)
        return applyRotation(node.rotation, to: unrotated)
    }

    /// Der Hüllrahmen eines Knotens in Dokumentkoordinaten, inklusive Rotation.
    public static func bounds(for node: Node) -> CGRect {
        path(for: node).bounds
    }

    /// Die Kontur ohne Rotation — Grundlage sowohl für ``path(for:)`` als auch,
    /// um den Rotationsmittelpunkt (Mittelpunkt des *unrotierten* Hüllrahmens)
    /// zu bestimmen.
    private static func unrotatedPath(for node: Node) -> VectorPath {
        switch node.content {
        case let .shape(spec):
            return ShapeGeometry.path(for: spec)
        case let .path(vectorPath):
            return vectorPath
        case let .text(spec):
            // Textknoten werden für Darstellung, Treffertest und Export gleich
            // behandelt wie jede andere Kontur — dieselbe Umwandlung, die auch
            // „Text in Pfade umwandeln" verwendet. Dadurch kann es zwischen
            // dem, was am Bildschirm steht, und dem, was exportiert wird, gar
            // nicht erst auseinanderlaufen.
            return TextToPath.path(for: spec)
        case let .group(children):
            // Teilpfade der Kinder werden aneinandergehängt statt geometrisch
            // vereinigt (keine boolesche Operation) — für Bounds und Rendering
            // reicht das; eine echte Verschmelzung wäre eine explizite
            // Boolean-Operation auf den Kindpfaden, kein impliziter Nebeneffekt
            // der Gruppierung.
            let childSubpaths = children.map(path(for:)).flatMap(\.subpaths)
            return VectorPath(subpaths: childSubpaths)
        }
    }

    /// Dreht einen Pfad um den Mittelpunkt seines eigenen Hüllrahmens.
    ///
    /// Bei `angle == 0` wird bewusst keine Transformation angewandt: Auch eine
    /// Identitäts-Matrix reproduziert Fliesskommawerte durch die Multiplikation
    /// nicht immer exakt. Unrotierte Geometrie soll aber Zahl für Zahl die
    /// bleiben, die eingegeben wurde — sonst wandern Koordinaten allein durchs
    /// Anschauen.
    private static func applyRotation(_ angle: CGFloat, to path: VectorPath) -> VectorPath {
        guard angle != 0, !path.isEmpty else { return path }

        let bounds = path.bounds
        guard !bounds.isNull else { return path }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: angle)
            .translatedBy(x: -center.x, y: -center.y)

        return path.applying(transform)
    }
}
