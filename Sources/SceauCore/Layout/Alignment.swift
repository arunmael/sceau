import CoreGraphics

/// Woran ausgerichtet wird.
public enum AlignmentEdge: String, Sendable, CaseIterable {
    case left, centerX, right
    case top, centerY, bottom

    var isHorizontal: Bool {
        switch self {
        case .left, .centerX, .right: return true
        case .top, .centerY, .bottom: return false
        }
    }
}

/// Achse für Verteilen und Spiegeln.
public enum Axis: String, Sendable, CaseIterable {
    case horizontal, vertical
}

/// Ausrichten und Verteilen von Rahmen.
///
/// Die Funktionen liefern **Verschiebungen** statt fertiger Rahmen. Damit
/// bleibt die Entscheidung, wie eine Verschiebung auf einen Knoten wirkt
/// (parametrische Form, Pfad, Gruppe), an einer einzigen Stelle —
/// ``NodeTransform`` — statt sich hier zu wiederholen.
public enum LayoutOps {

    /// Richtet Rahmen an einer Kante aus.
    ///
    /// - Parameter container: Bezugsrahmen. Wird `nil` übergeben, dienen die
    ///   Rahmen selbst als Bezug (übliches Verhalten bei mehreren Objekten).
    ///   Bei genau einem Objekt ist der sinnvolle Bezug die Zeichenfläche —
    ///   das entscheidet der Aufrufer.
    /// - Returns: Pro Eingaberahmen die nötige Verschiebung, in gleicher Reihenfolge.
    public static func align(
        _ rects: [CGRect],
        to edge: AlignmentEdge,
        within container: CGRect? = nil
    ) -> [CGVector] {
        guard !rects.isEmpty else { return [] }
        let reference = container ?? boundingBox(of: rects)
        guard !reference.isNull else { return rects.map { _ in .zero } }

        return rects.map { rect in
            switch edge {
            case .left: return CGVector(dx: reference.minX - rect.minX, dy: 0)
            case .centerX: return CGVector(dx: reference.midX - rect.midX, dy: 0)
            case .right: return CGVector(dx: reference.maxX - rect.maxX, dy: 0)
            case .top: return CGVector(dx: 0, dy: reference.minY - rect.minY)
            case .centerY: return CGVector(dx: 0, dy: reference.midY - rect.midY)
            case .bottom: return CGVector(dx: 0, dy: reference.maxY - rect.maxY)
            }
        }
    }

    /// Verteilt Rahmen mit gleichen Abständen zwischen ihren Kanten.
    ///
    /// Die beiden äusseren Rahmen bleiben stehen und spannen die Strecke auf —
    /// das ist das Verhalten, das Gestaltungsprogramme durchweg verwenden und
    /// das Nutzer erwarten. Bei weniger als drei Rahmen gibt es nichts zu
    /// verteilen.
    public static func distribute(_ rects: [CGRect], along axis: Axis) -> [CGVector] {
        guard rects.count >= 3 else { return rects.map { _ in .zero } }

        // Nach Position sortieren, aber die ursprüngliche Reihenfolge merken,
        // damit die Verschiebungen wieder richtig zugeordnet werden.
        let indexed = rects.enumerated().sorted { lhs, rhs in
            axis == .horizontal ? lhs.element.minX < rhs.element.minX : lhs.element.minY < rhs.element.minY
        }

        let sorted = indexed.map(\.element)
        let extent: (CGRect) -> CGFloat = { axis == .horizontal ? $0.width : $0.height }
        let start: (CGRect) -> CGFloat = { axis == .horizontal ? $0.minX : $0.minY }
        let end: (CGRect) -> CGFloat = { axis == .horizontal ? $0.maxX : $0.maxY }

        guard let first = sorted.first, let last = sorted.last else { return rects.map { _ in .zero } }

        let span = end(last) - start(first)
        let occupied = sorted.reduce(0) { $0 + extent($1) }
        let gap = (span - occupied) / CGFloat(sorted.count - 1)

        var offsets = [CGVector](repeating: .zero, count: rects.count)
        var cursor = start(first)

        for (position, entry) in indexed.enumerated() {
            let rect = entry.element
            // Die beiden äusseren Rahmen bleiben stehen; der erste setzt nur
            // den Startpunkt für die Kette dahinter.
            if position == 0 {
                cursor = end(rect) + gap
                continue
            }
            if position == indexed.count - 1 { continue }
            let delta = cursor - start(rect)
            offsets[entry.offset] = axis == .horizontal
                ? CGVector(dx: delta, dy: 0)
                : CGVector(dx: 0, dy: delta)
            cursor += extent(rect) + gap
        }

        return offsets
    }

    /// Der gemeinsame Hüllrahmen mehrerer Rahmen.
    public static func boundingBox(of rects: [CGRect]) -> CGRect {
        rects.reduce(CGRect.null) { $0.union($1) }
    }
}
