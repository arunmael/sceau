import CoreGraphics

/// Flacht kubische Bézier-Segmente zu Polyzügen ab.
///
/// Boolesche Operationen (``BooleanOperator``) rechnen über `iOverlay` auf
/// Polygonen, nicht auf Kurven. Da ein späteres Zurückfitten von Kurven aus
/// dem Polygon-Ergebnis bewusst aufgeschoben ist, muss die Abflach-Toleranz
/// ein **Parameter** bleiben statt fest verdrahtet zu sein — je nach
/// Anwendungsfall (Vorschau vs. Export) kann später eine andere Genauigkeit
/// gewünscht sein.
public enum Flattener {

    /// Vorgabetoleranz in Punkt — maximaler Abstand des Polyzugs zur echten Kurve.
    public static let defaultTolerance: CGFloat = 0.05

    /// Begrenzt die Rekursionstiefe der adaptiven Unterteilung, damit entartete
    /// Kurven (z. B. Kontrollpunkte weit ausserhalb bei zusammenfallenden
    /// Endpunkten) nicht in eine Endlosrekursion laufen.
    private static let maxRecursionDepth = 24

    /// Flacht ein Segment ab. Ergebnis enthält den Endpunkt, **nicht** den Startpunkt
    /// — so lassen sich die Ergebnisse mehrerer Segmente eines Teilpfads einfach
    /// aneinanderhängen, ohne Knotenpunkte zu duplizieren.
    public static func flatten(_ segment: CubicSegment, tolerance: CGFloat) -> [CGPoint] {
        guard !segment.isLine else { return [segment.end] }

        // Eine Toleranz <= 0 wäre eine Endlosunterteilung ohne die
        // Tiefenbegrenzung — die Rekursion bleibt trotzdem sicher, aber wir
        // behandeln nicht-positive Werte wie "so fein wie möglich" statt sie
        // als Fehler zu werten.
        let safeTolerance = max(tolerance, 0)

        var result: [CGPoint] = []
        subdivide(segment, tolerance: safeTolerance, depth: 0, into: &result)
        return result
    }

    /// Flacht einen ganzen Pfad zu geschlossenen Polygonringen ab.
    ///
    /// Offene Teilpfade werden für die boolesche Verarbeitung implizit
    /// geschlossen (die Schlusskante von letztem zu erstem Punkt wird nicht
    /// als expliziter Punkt hinzugefügt — Konsumenten wie `iOverlay` fassen
    /// jeden Ring ohnehin als geschlossen auf). Ringe mit weniger als drei
    /// Punkten sind keine gültige Fläche und werden weggelassen.
    public static func polygons(of path: VectorPath, tolerance: CGFloat) -> [[CGPoint]] {
        var rings: [[CGPoint]] = []
        rings.reserveCapacity(path.subpaths.count)

        for subpath in path.subpaths {
            guard let first = subpath.anchors.first else { continue }

            var ring: [CGPoint] = [first.point]
            for segment in subpath.segments {
                ring.append(contentsOf: flatten(segment, tolerance: tolerance))
            }

            // Bei geschlossenen Teilpfaden enthält `subpath.segments` bereits
            // das Schlusssegment zurück zum ersten Anker — dessen Endpunkt ist
            // exakt `first.point` und würde den Ring doppelt schliessen.
            if subpath.isClosed, ring.count > 1, ring.last == first.point {
                ring.removeLast()
            }

            guard ring.count >= 3 else { continue }
            rings.append(ring)
        }

        return rings
    }

    // MARK: - Adaptive Unterteilung

    private static func subdivide(
        _ segment: CubicSegment,
        tolerance: CGFloat,
        depth: Int,
        into result: inout [CGPoint]
    ) {
        if depth >= maxRecursionDepth || isFlatEnough(segment, tolerance: tolerance) {
            result.append(segment.end)
            return
        }

        let (left, right) = split(segment)
        subdivide(left, tolerance: tolerance, depth: depth + 1, into: &result)
        subdivide(right, tolerance: tolerance, depth: depth + 1, into: &result)
    }

    /// Flachheitsmass: Abstand beider Kontrollpunkte zur Sehne (Start-Ende-Gerade).
    /// Liegen beide innerhalb der Toleranz, weicht die Kurve auf diesem Abschnitt
    /// kaum von einer Geraden ab — die Sehne selbst genügt als Näherung.
    private static func isFlatEnough(_ segment: CubicSegment, tolerance: CGFloat) -> Bool {
        let d1 = distance(segment.control1, toLineFrom: segment.start, to: segment.end)
        let d2 = distance(segment.control2, toLineFrom: segment.start, to: segment.end)
        return d1 <= tolerance && d2 <= tolerance
    }

    private static func distance(_ point: CGPoint, toLineFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy

        // Start und Ende fallen zusammen (z. B. eine Schleife, die exakt zu
        // ihrem Ausgangspunkt zurückkehrt) — dann ist "Abstand zur Sehne"
        // undefiniert, wir nehmen stattdessen den Abstand zum Punkt selbst.
        guard lengthSquared > .ulpOfOne else {
            return hypot(point.x - a.x, point.y - a.y)
        }

        let cross = (point.x - a.x) * dy - (point.y - a.y) * dx
        return abs(cross) / lengthSquared.squareRoot()
    }

    /// Teilt ein kubisches Segment per De-Casteljau bei t=0.5 in zwei kubische
    /// Segmente, die zusammen exakt dieselbe Kurve beschreiben.
    private static func split(_ segment: CubicSegment) -> (CubicSegment, CubicSegment) {
        let p0 = segment.start
        let p1 = segment.control1
        let p2 = segment.control2
        let p3 = segment.end

        let p01 = midpoint(p0, p1)
        let p12 = midpoint(p1, p2)
        let p23 = midpoint(p2, p3)
        let p012 = midpoint(p01, p12)
        let p123 = midpoint(p12, p23)
        let p0123 = midpoint(p012, p123)

        let left = CubicSegment(start: p0, control1: p01, control2: p012, end: p0123)
        let right = CubicSegment(start: p0123, control1: p123, control2: p23, end: p3)
        return (left, right)
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}
