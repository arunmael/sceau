import CoreGraphics

/// Baut aus einer grob abgetasteten Mauszug-Punktfolge (viele, dicht liegende
/// Punkte) einen geglätteten, offenen Bézier-Pfad.
///
/// Zwei Schritte, wie beim Freihandzeichnen üblich:
/// 1. **Vereinfachen** (Douglas-Peucker): unnötige, fast auf der Linie
///    liegende Zwischenpunkte verwerfen — sonst hätte jeder Strich Hunderte
///    Anker und liesse sich später kaum noch von Hand nachbearbeiten.
/// 2. **Glätten** (Catmull-Rom → kubische Bézier): aus den verbliebenen
///    Punkten eine durch alle Punkte laufende, weiche Kurve statt eines
///    kantigen Polyzugs bauen.
///
/// Reine Vektor-Pfad-Kernlogik — bewusst von Hand geschrieben statt
/// delegiert, siehe agent-rules.md Abschnitt 7.
public enum FreehandStroke {

    /// Deckel gegen eine ausufernde Punktzahl bei einer sehr langen oder sehr
    /// langsamen Zugbewegung (jedes `mouseDragged` fügt einen Punkt hinzu) —
    /// ohne ihn würde Douglas-Peucker auf Zehntausenden Punkten rechnen und
    /// die Zeichenfläche beim Loslassen kurz einfrieren.
    public static let maxInputPoints = 4000

    /// Baut den geglätteten Pfad. `smoothingTolerance` ist der maximale
    /// Abstand (in Dokumentpunkten), den ein verworfener Zwischenpunkt von
    /// der vereinfachten Linie haben darf — 0 behält jeden Punkt.
    public static func path(from rawPoints: [CGPoint], smoothingTolerance: CGFloat) -> VectorPath {
        let points = downsampled(rawPoints)

        guard points.count >= 2 else {
            if let only = points.first {
                // Ein Tupfer (Klick ohne Zugbewegung): ein winziges, aber
                // sichtbares Liniensegment statt eines leeren, unsichtbaren
                // Pfads — sonst verschwindet ein einfacher Klick spurlos.
                let epsilon: CGFloat = 0.01
                let a = Anchor(corner: CGPoint(x: only.x - epsilon, y: only.y))
                let b = Anchor(corner: CGPoint(x: only.x + epsilon, y: only.y))
                return VectorPath(subpath: Subpath(anchors: [a, b], isClosed: false))
            }
            return VectorPath()
        }

        let simplified = douglasPeucker(points, tolerance: max(0, smoothingTolerance))
        return VectorPath(subpath: catmullRomSubpath(simplified))
    }

    /// Reduziert eine zu lange Rohpunktfolge gleichmässig auf ``maxInputPoints``,
    /// bevor überhaupt vereinfacht wird — Anfang und Ende bleiben dabei erhalten.
    private static func downsampled(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > maxInputPoints else { return points }
        let stride = Double(points.count) / Double(maxInputPoints)
        var result: [CGPoint] = []
        result.reserveCapacity(maxInputPoints)
        var index = 0.0
        while index < Double(points.count) {
            result.append(points[Int(index)])
            index += stride
        }
        if result.last != points.last { result.append(points[points.count - 1]) }
        return result
    }

    // MARK: - Douglas-Peucker

    /// Iterativ statt rekursiv: Bei fast geradlinigen, aber leicht
    /// verrauschten Eingaben (typisch für eine echte Mauszugbewegung) kann
    /// die Rekursion im ungünstigsten Fall bis zur vollen Punktzahl tief
    /// werden — bei mehreren tausend Punkten reicht das, um den Stack zum
    /// Überlaufen zu bringen. Ein eigenes Arbeits-"Stack"-Array auf dem Heap
    /// kennt diese Grenze nicht.
    private static func douglasPeucker(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2, tolerance > 0 else { return points }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var workStack: [(start: Int, end: Int)] = [(0, points.count - 1)]
        while let (start, end) = workStack.popLast() {
            guard end > start + 1 else { continue }

            var maxDistance: CGFloat = 0
            var splitIndex = start
            for index in (start + 1)..<end {
                let distance = perpendicularDistance(points[index], lineStart: points[start], lineEnd: points[end])
                if distance > maxDistance {
                    maxDistance = distance
                    splitIndex = index
                }
            }

            guard maxDistance > tolerance else { continue }

            keep[splitIndex] = true
            workStack.append((start, splitIndex))
            workStack.append((splitIndex, end))
        }

        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    private static func perpendicularDistance(_ point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else {
            // Entartete "Linie" (Start == Ende): der Abstand zum Punkt selbst.
            let ddx = point.x - lineStart.x
            let ddy = point.y - lineStart.y
            return (ddx * ddx + ddy * ddy).squareRoot()
        }

        // Fläche des von den drei Punkten aufgespannten Parallelogramms
        // (Kreuzprodukt), geteilt durch die Grundlinienlänge — die klassische
        // Punkt-zu-Gerade-Abstandsformel ohne Fallunterscheidung.
        let cross = abs(dx * (lineStart.y - point.y) - dy * (lineStart.x - point.x))
        return cross / lengthSquared.squareRoot()
    }

    // MARK: - Catmull-Rom → kubische Bézier

    private static func catmullRomSubpath(_ points: [CGPoint]) -> Subpath {
        guard points.count >= 2 else {
            return Subpath(anchors: points.map(Anchor.init(corner:)), isClosed: false)
        }
        guard points.count > 2 else {
            // Genau zwei Punkte: eine gerade Strecke, für die eine Catmull-
            // Rom-Krümmung ohnehin nichts beizutragen hätte.
            return Subpath(anchors: points.map(Anchor.init(corner:)), isClosed: false)
        }

        var anchors: [Anchor] = []
        anchors.reserveCapacity(points.count)

        for index in points.indices {
            // Offene Kurve: An den Enden wird der fehlende Nachbarpunkt durch
            // eine Spiegelung des jeweils übernächsten ersetzt (Standardtrick
            // für Catmull-Rom an offenen Rändern), statt die Kurve dort
            // künstlich zu schliessen.
            let p0 = index > 0 ? points[index - 1] : mirrored(points[1], around: points[0])
            let p1 = points[index]
            let p2 = index < points.count - 1 ? points[index + 1] : mirrored(points[points.count - 2], around: points[points.count - 1])
            let p3Index = index + 2
            let p3 = p3Index < points.count ? points[p3Index] : mirrored(p1, around: p2)

            // Standard-Umrechnung Catmull-Rom -> Bézier-Griffe für den Anker
            // an `p1`: Der eingehende Griff hängt vom Vorgänger/Nachfolger
            // dieses Ankers ab, der ausgehende vom jeweils jetzigen Nachbarn.
            let controlIn = CGPoint(
                x: p1.x - (p2.x - p0.x) / 6,
                y: p1.y - (p2.y - p0.y) / 6
            )
            let controlOut = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            _ = p3 // p3 fliesst über den nächsten Schleifendurchlauf (als dessen p2) ein.

            anchors.append(Anchor(
                point: p1,
                controlIn: index == 0 ? p1 : controlIn,
                controlOut: index == points.count - 1 ? p1 : controlOut,
                style: .smooth
            ))
        }

        return Subpath(anchors: anchors, isClosed: false)
    }

    private static func mirrored(_ point: CGPoint, around center: CGPoint) -> CGPoint {
        CGPoint(x: 2 * center.x - point.x, y: 2 * center.y - point.y)
    }
}
