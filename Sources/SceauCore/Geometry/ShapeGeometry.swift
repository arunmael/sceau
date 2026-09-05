import CoreGraphics

/// Löst parametrische Grundformen (``ShapeSpec``) in ihre ``VectorPath``-Darstellung auf.
///
/// Diese Auflösung ist bewusst eine reine Funktion ohne Zustand: Eine Grundform
/// bleibt im Dokumentmodell parametrisch (siehe ``ShapeSpec``), und erst wenn eine
/// Operation tatsächliche Anker braucht (Rendern, Export, Zeichenstift-Bearbeitung,
/// boolesche Verknüpfung), wird hier auf Anfrage eine ``VectorPath`` gebaut.
public enum ShapeGeometry {

    /// Kappa-Konstante: Verhältnis von Bézier-Griffweite zu Radius, mit dem ein
    /// Viertelkreisbogen am besten durch eine kubische Kurve angenähert wird.
    /// Herleitung: 4/3 * (sqrt(2) - 1).
    private static let kappa: CGFloat = 0.5522847498307936

    /// Ein fester Exponent hält die App-Icon-Silhouette über alle Grössen hinweg
    /// konsistent, statt sie zu einem frei veränderlichen Formparameter zu machen.
    private static let superellipseExponent: CGFloat = 5

    /// Löst eine parametrische Grundform in ihre Pfaddarstellung auf.
    public static func path(for spec: ShapeSpec) -> VectorPath {
        let frame = spec.frame
        // `CGRect.width`/`.height` sind bereits normalisiert (liefern stets den
        // Betrag) — ein mit negativer Grösse gebautes Rechteck rutschte hier
        // also unbemerkt durch. Die rohen `size`-Komponenten behalten das
        // Vorzeichen.
        guard frame.size.width > 0, frame.size.height > 0 else { return VectorPath() }

        // Nicht endliche Werte dürfen unter keinen Umständen in die Geometrie
        // gelangen: Sie pflanzen sich durch Hüllrahmen, Abflachung und Export
        // fort und sind dort nicht mehr als Ursache erkennbar. Über die
        // Zahlenfelder des Inspektors sind sie erreichbar.
        guard frame.isFiniteRect else { return VectorPath() }

        switch spec {
        case let .rectangle(frame, cornerRadius):
            return rectanglePath(frame: frame, cornerRadius: cornerRadius)
        case let .ellipse(frame):
            return ellipsePath(frame: frame)
        case let .polygon(frame, sides):
            return polygonPath(frame: frame, sides: sides)
        case let .star(frame, points, innerRatio):
            return starPath(frame: frame, points: points, innerRatio: innerRatio)
        case let .squircle(frame):
            return squirclePath(frame: frame)
        case let .heart(frame):
            return heartPath(frame: frame)
        case let .arrow(frame, shaftRatio):
            return arrowPath(frame: frame, shaftRatio: shaftRatio)
        case let .speechBubble(frame, cornerRadius):
            return speechBubblePath(frame: frame, cornerRadius: cornerRadius)
        case let .cross(frame, armRatio):
            return crossPath(frame: frame, armRatio: armRatio)
        }
    }

    // MARK: - Rechteck

    private static func rectanglePath(frame: CGRect, cornerRadius: CGFloat) -> VectorPath {
        guard cornerRadius > 0 else {
            let anchors = [
                Anchor(corner: CGPoint(x: frame.minX, y: frame.minY)),
                Anchor(corner: CGPoint(x: frame.maxX, y: frame.minY)),
                Anchor(corner: CGPoint(x: frame.maxX, y: frame.maxY)),
                Anchor(corner: CGPoint(x: frame.minX, y: frame.maxY))
            ]
            return VectorPath(subpath: Subpath(anchors: anchors, isClosed: true))
        }

        let radius = min(cornerRadius, min(frame.width, frame.height) / 2)
        let handle = kappa * radius

        // Vier Eckanker, jeweils mit Griffen entlang der beiden angrenzenden
        // Kanten — der Bogen läuft über den Eckpunkt der jeweils abgerundeten Ecke.
        // Reihenfolge: links-oben -> rechts-oben -> rechts-unten -> links-unten,
        // jede Ecke bekommt zwei Anker (Kurvenbeginn und -ende), damit die Kanten
        // zwischen den Ecken gerade bleiben.
        let topLeft = CGPoint(x: frame.minX, y: frame.minY)
        let topRight = CGPoint(x: frame.maxX, y: frame.minY)
        let bottomRight = CGPoint(x: frame.maxX, y: frame.maxY)
        let bottomLeft = CGPoint(x: frame.minX, y: frame.maxY)

        // Anker liegen an den Kurvenenden (den Tangentenpunkten), nicht in den
        // geometrischen Ecken selbst: acht Stück, zwei je Ecke. Die Griffe der
        // geraden Kantenstücke liegen auf ihrem eigenen Anker und haben damit
        // keine Kurvenwirkung — so beschreiben die Bögen exakt die Rundung,
        // während die Kanten dazwischen wirklich gerade bleiben.
        var anchors: [Anchor] = []

        // Oben-links -> Oben-rechts (obere Kante), dann Bogen bei oben-rechts.
        anchors.append(
            Anchor(
                point: CGPoint(x: topLeft.x + radius, y: topLeft.y),
                controlIn: CGPoint(x: topLeft.x + radius, y: topLeft.y),
                controlOut: CGPoint(x: topLeft.x + radius, y: topLeft.y),
                style: .smooth
            )
        )
        anchors.append(
            Anchor(
                point: CGPoint(x: topRight.x - radius, y: topRight.y),
                controlIn: CGPoint(x: topRight.x - radius, y: topRight.y),
                controlOut: CGPoint(x: topRight.x - radius + handle, y: topRight.y),
                style: .smooth
            )
        )
        anchors.append(
            Anchor(
                point: CGPoint(x: topRight.x, y: topRight.y + radius),
                controlIn: CGPoint(x: topRight.x, y: topRight.y + radius - handle),
                controlOut: CGPoint(x: topRight.x, y: topRight.y + radius),
                style: .smooth
            )
        )
        anchors.append(
            Anchor(
                point: CGPoint(x: bottomRight.x, y: bottomRight.y - radius),
                controlIn: CGPoint(x: bottomRight.x, y: bottomRight.y - radius),
                controlOut: CGPoint(x: bottomRight.x, y: bottomRight.y - radius + handle),
                style: .smooth
            )
        )
        anchors.append(
            Anchor(
                point: CGPoint(x: bottomRight.x - radius, y: bottomRight.y),
                controlIn: CGPoint(x: bottomRight.x - radius + handle, y: bottomRight.y),
                controlOut: CGPoint(x: bottomRight.x - radius, y: bottomRight.y),
                style: .smooth
            )
        )
        anchors.append(
            Anchor(
                point: CGPoint(x: bottomLeft.x + radius, y: bottomLeft.y),
                controlIn: CGPoint(x: bottomLeft.x + radius, y: bottomLeft.y),
                controlOut: CGPoint(x: bottomLeft.x + radius - handle, y: bottomLeft.y),
                style: .smooth
            )
        )
        anchors.append(
            Anchor(
                point: CGPoint(x: bottomLeft.x, y: bottomLeft.y - radius),
                controlIn: CGPoint(x: bottomLeft.x, y: bottomLeft.y - radius + handle),
                controlOut: CGPoint(x: bottomLeft.x, y: bottomLeft.y - radius),
                style: .smooth
            )
        )
        anchors.append(
            Anchor(
                point: CGPoint(x: topLeft.x, y: topLeft.y + radius),
                controlIn: CGPoint(x: topLeft.x, y: topLeft.y + radius),
                controlOut: CGPoint(x: topLeft.x, y: topLeft.y + radius - handle),
                style: .smooth
            )
        )

        return VectorPath(subpath: Subpath(anchors: anchors, isClosed: true))
    }

    // MARK: - Ellipse

    private static func ellipsePath(frame: CGRect) -> VectorPath {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let a = frame.width / 2
        let b = frame.height / 2
        let hx = kappa * a
        let hy = kappa * b

        let top = CGPoint(x: center.x, y: center.y - b)
        let right = CGPoint(x: center.x + a, y: center.y)
        let bottom = CGPoint(x: center.x, y: center.y + b)
        let left = CGPoint(x: center.x - a, y: center.y)

        let anchors = [
            Anchor(
                point: top,
                controlIn: CGPoint(x: top.x - hx, y: top.y),
                controlOut: CGPoint(x: top.x + hx, y: top.y),
                style: .symmetric
            ),
            Anchor(
                point: right,
                controlIn: CGPoint(x: right.x, y: right.y - hy),
                controlOut: CGPoint(x: right.x, y: right.y + hy),
                style: .symmetric
            ),
            Anchor(
                point: bottom,
                controlIn: CGPoint(x: bottom.x + hx, y: bottom.y),
                controlOut: CGPoint(x: bottom.x - hx, y: bottom.y),
                style: .symmetric
            ),
            Anchor(
                point: left,
                controlIn: CGPoint(x: left.x, y: left.y + hy),
                controlOut: CGPoint(x: left.x, y: left.y - hy),
                style: .symmetric
            )
        ]

        return VectorPath(subpath: Subpath(anchors: anchors, isClosed: true))
    }

    // MARK: - Squircle

    private static func squirclePath(frame: CGRect) -> VectorPath {
        let sampleCount = 64
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let a = frame.width / 2
        let b = frame.height / 2
        let power = 2 / superellipseExponent

        // Genügend dichte Eckanker vermeiden Bézier-Sonderfälle an den Achsen;
        // der Betrag hält die gebrochene Potenz auch bei negativen Anteilen reell.
        var anchors: [Anchor] = []
        anchors.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(sampleCount)
            let cosT = cos(angle)
            let sinT = sin(angle)
            let x = a * pow(abs(cosT), power) * (cosT < 0 ? -1 : 1)
            let y = b * pow(abs(sinT), power) * (sinT < 0 ? -1 : 1)
            anchors.append(Anchor(corner: CGPoint(x: center.x + x, y: center.y + y)))
        }

        return VectorPath(subpath: Subpath(anchors: anchors, isClosed: true))
    }

    // MARK: - Herz

    /// Herz aus vier kubischen Segmenten in einem normierten Koordinatensystem
    /// `u,v ∈ [-1,1]` (v nach unten wie im Dokument), anschliessend achsenweise
    /// unabhängig auf den Rahmen skaliert. Jeder Anker, der einen Rand berührt
    /// (die beiden Lappenspitzen oben, die beiden äussersten Punkte links/rechts,
    /// die Spitze unten), bekommt an genau dieser Stelle einen waagrechten bzw.
    /// senkrechten Griff — nur so garantiert die Kurve, dass ihr tatsächlicher
    /// Hüllrahmen (der die Bézier-Extrema mit einschliesst, nicht nur die Anker)
    /// exakt den vorgegebenen Rahmen trifft, statt ihn zu über- oder
    /// unterschreiten.
    private static func heartPath(frame: CGRect) -> VectorPath {
        func map(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: frame.midX + u * frame.width / 2, y: frame.midY + v * frame.height / 2)
        }

        let bottom = Anchor(
            point: map(0, 1),
            controlIn: map(-0.3, 0.85),
            controlOut: map(0.3, 0.85),
            style: .corner
        )
        let rightOuter = Anchor(
            point: map(1, -0.3),
            controlIn: map(1, 0),
            controlOut: map(1, -0.6),
            style: .smooth
        )
        let rightLobe = Anchor(
            point: map(0.5, -1),
            controlIn: map(0.75, -1),
            controlOut: map(0.25, -1),
            style: .smooth
        )
        let topDip = Anchor(
            point: map(0, -0.4),
            controlIn: map(0.15, -0.6),
            controlOut: map(-0.15, -0.6),
            style: .symmetric
        )
        let leftLobe = Anchor(
            point: map(-0.5, -1),
            controlIn: map(-0.25, -1),
            controlOut: map(-0.75, -1),
            style: .smooth
        )
        let leftOuter = Anchor(
            point: map(-1, -0.3),
            controlIn: map(-1, -0.6),
            controlOut: map(-1, 0),
            style: .smooth
        )

        return VectorPath(subpath: Subpath(
            anchors: [bottom, rightOuter, rightLobe, topDip, leftLobe, leftOuter],
            isClosed: true
        ))
    }

    // MARK: - Pfeil

    /// Fester Anteil der Rahmenbreite für die Pfeilspitze — siehe
    /// ``ShapeSpec/arrow(frame:shaftRatio:)``.
    private static let arrowHeadRatio: CGFloat = 1.0 / 3

    private static func arrowPath(frame: CGRect, shaftRatio: CGFloat) -> VectorPath {
        let halfThickness = min(1, max(0, shaftRatio))
        let headStart = 1 - arrowHeadRatio

        func map(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: frame.minX + u * frame.width, y: frame.midY + v * frame.height / 2)
        }

        // Gerade Kanten — ein Pfeil ist keine Kurvenform, deshalb ausschliesslich
        // Eckpunkte ohne Griffwirkung, analog zu Polygon/Stern.
        let points: [CGPoint] = [
            map(0, -halfThickness),
            map(headStart, -halfThickness),
            map(headStart, -1),
            map(1, 0),
            map(headStart, 1),
            map(headStart, halfThickness),
            map(0, halfThickness)
        ]

        return VectorPath(subpath: Subpath(anchors: points.map(Anchor.init(corner:)), isClosed: true))
    }

    // MARK: - Sprechblase

    /// Fester Anteil der Rahmenhöhe für den Schwanz — siehe
    /// ``ShapeSpec/speechBubble(frame:cornerRadius:)``.
    private static let speechBubbleTailHeightRatio: CGFloat = 0.22

    private static func speechBubblePath(frame: CGRect, cornerRadius: CGFloat) -> VectorPath {
        let tailHeight = frame.height * speechBubbleTailHeightRatio
        let bubble = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - tailHeight)
        guard bubble.width > 0, bubble.height > 0 else { return VectorPath() }

        let radius = min(max(0, cornerRadius), min(bubble.width, bubble.height) / 2)
        let handle = kappa * radius

        let topLeft = CGPoint(x: bubble.minX, y: bubble.minY)
        let topRight = CGPoint(x: bubble.maxX, y: bubble.minY)
        let bottomRight = CGPoint(x: bubble.maxX, y: bubble.maxY)
        let bottomLeft = CGPoint(x: bubble.minX, y: bubble.maxY)

        // Schwanz sitzt im geraden Stück der unteren Kante, nahe der linken
        // Ecke. Ist dafür nach Abzug beider Eckenradien kein Platz mehr (sehr
        // grosser Eckradius auf schmalem Rahmen), entfällt der Schwanz — eine
        // reine abgerundete Fläche ist dann immer noch ein gültiges, nicht
        // entartetes Ergebnis, statt mit negativer Breite abzustürzen.
        let straightBottom = bottomRight.x - radius - (bottomLeft.x + radius)
        let tailWidth = max(0, min(frame.width * 0.22, straightBottom * 0.6))
        let tailInset = max(0, straightBottom * 0.15)
        let tailBaseLeft = CGPoint(x: bottomLeft.x + radius + tailInset, y: bottomLeft.y)
        let tailBaseRight = CGPoint(x: tailBaseLeft.x + tailWidth, y: bottomLeft.y)
        let tailApex = CGPoint(x: tailBaseLeft.x + tailWidth * 0.25, y: frame.maxY)
        let hasTail = tailWidth > 0

        // Baut auf denselben acht Ankern wie ``rectanglePath`` auf (zwei je
        // Ecke, gerade Kanten dazwischen) — nur dass die untere Kante bei
        // vorhandenem Schwanz drei zusätzliche Eckpunkte für das Dreieck bekommt.
        var anchors: [Anchor] = []

        // Oben-links -> oben-rechts (obere Kante), dann Bogen bei oben-rechts.
        anchors.append(Anchor(
            point: CGPoint(x: topLeft.x + radius, y: topLeft.y),
            controlIn: CGPoint(x: topLeft.x + radius, y: topLeft.y),
            controlOut: CGPoint(x: topLeft.x + radius, y: topLeft.y),
            style: .smooth
        ))
        anchors.append(Anchor(
            point: CGPoint(x: topRight.x - radius, y: topRight.y),
            controlIn: CGPoint(x: topRight.x - radius, y: topRight.y),
            controlOut: CGPoint(x: topRight.x - radius + handle, y: topRight.y),
            style: .smooth
        ))
        anchors.append(Anchor(
            point: CGPoint(x: topRight.x, y: topRight.y + radius),
            controlIn: CGPoint(x: topRight.x, y: topRight.y + radius - handle),
            controlOut: CGPoint(x: topRight.x, y: topRight.y + radius),
            style: .smooth
        ))
        // Rechte Kante, dann Bogen unten rechts.
        anchors.append(Anchor(
            point: CGPoint(x: bottomRight.x, y: bottomRight.y - radius),
            controlIn: CGPoint(x: bottomRight.x, y: bottomRight.y - radius),
            controlOut: CGPoint(x: bottomRight.x, y: bottomRight.y - radius + handle),
            style: .smooth
        ))
        anchors.append(Anchor(
            point: CGPoint(x: bottomRight.x - radius, y: bottomRight.y),
            controlIn: CGPoint(x: bottomRight.x - radius + handle, y: bottomRight.y),
            controlOut: CGPoint(x: bottomRight.x - radius, y: bottomRight.y),
            style: .smooth
        ))
        // Untere Kante — mit Schwanz-Dreieck, falls Platz dafür ist.
        if hasTail {
            anchors.append(Anchor(corner: tailBaseRight))
            anchors.append(Anchor(corner: tailApex))
            anchors.append(Anchor(corner: tailBaseLeft))
        }
        anchors.append(Anchor(
            point: CGPoint(x: bottomLeft.x + radius, y: bottomLeft.y),
            controlIn: CGPoint(x: bottomLeft.x + radius, y: bottomLeft.y),
            controlOut: CGPoint(x: bottomLeft.x + radius - handle, y: bottomLeft.y),
            style: .smooth
        ))
        // Bogen unten links.
        anchors.append(Anchor(
            point: CGPoint(x: bottomLeft.x, y: bottomLeft.y - radius),
            controlIn: CGPoint(x: bottomLeft.x, y: bottomLeft.y - radius + handle),
            controlOut: CGPoint(x: bottomLeft.x, y: bottomLeft.y - radius),
            style: .smooth
        ))
        // Linke Kante, dann Bogen oben links (schliesst zurück zum ersten Anker).
        anchors.append(Anchor(
            point: CGPoint(x: topLeft.x, y: topLeft.y + radius),
            controlIn: CGPoint(x: topLeft.x, y: topLeft.y + radius),
            controlOut: CGPoint(x: topLeft.x, y: topLeft.y + radius - handle),
            style: .smooth
        ))

        return VectorPath(subpath: Subpath(anchors: anchors, isClosed: true))
    }

    // MARK: - Kreuz (Plus)

    private static func crossPath(frame: CGRect, armRatio: CGFloat) -> VectorPath {
        let ratio = min(1, max(0, armRatio))
        let thickness = ratio * min(frame.width, frame.height)
        let half = thickness / 2
        let cx = frame.midX
        let cy = frame.midY

        let points: [CGPoint] = [
            CGPoint(x: cx - half, y: frame.minY),
            CGPoint(x: cx + half, y: frame.minY),
            CGPoint(x: cx + half, y: cy - half),
            CGPoint(x: frame.maxX, y: cy - half),
            CGPoint(x: frame.maxX, y: cy + half),
            CGPoint(x: cx + half, y: cy + half),
            CGPoint(x: cx + half, y: frame.maxY),
            CGPoint(x: cx - half, y: frame.maxY),
            CGPoint(x: cx - half, y: cy + half),
            CGPoint(x: frame.minX, y: cy + half),
            CGPoint(x: frame.minX, y: cy - half),
            CGPoint(x: cx - half, y: cy - half)
        ]

        return VectorPath(subpath: Subpath(anchors: points.map(Anchor.init(corner:)), isClosed: true))
    }

    // MARK: - Polygon

    /// Obergrenze für Ecken/Zacken. Weit über jedem sinnvollen Gebrauch (der
    /// Inspektor erlaubt höchstens 24), aber endlich: `sides`/`points` kommen
    /// aus einer `Codable`-Datei ohne Bereichsprüfung beim Dekodieren — ohne
    /// Deckel löst ein manipulierter oder beschädigter Wert wie `Int.max`
    /// einen sofortigen `reserveCapacity`- bzw. Multiplikations-Overflow-Absturz
    /// aus, noch bevor überhaupt Geometrie berechnet wird.
    private static let maxPolygonOrStarCount = 1000

    private static func polygonPath(frame: CGRect, sides: Int) -> VectorPath {
        let count = min(max(3, sides), maxPolygonOrStarCount)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let a = frame.width / 2
        let b = frame.height / 2

        var anchors: [Anchor] = []
        anchors.reserveCapacity(count)
        for index in 0..<count {
            // Erste Ecke oben (-90°), im Uhrzeigersinn (Y wächst nach unten, also
            // steigender Winkel in Standardkonvention entspricht hier Uhrzeigersinn).
            let angle = -CGFloat.pi / 2 + 2 * CGFloat.pi * CGFloat(index) / CGFloat(count)
            let point = CGPoint(x: center.x + a * cos(angle), y: center.y + b * sin(angle))
            anchors.append(Anchor(corner: point))
        }

        return VectorPath(subpath: Subpath(anchors: anchors, isClosed: true))
    }

    // MARK: - Stern

    private static func starPath(frame: CGRect, points: Int, innerRatio: CGFloat) -> VectorPath {
        let count = min(max(3, points), maxPolygonOrStarCount)
        let ratio = min(1.0, max(0.01, innerRatio))
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let a = frame.width / 2
        let b = frame.height / 2

        var anchors: [Anchor] = []
        anchors.reserveCapacity(count * 2)
        for index in 0..<(count * 2) {
            let angle = -CGFloat.pi / 2 + CGFloat.pi * CGFloat(index) / CGFloat(count)
            let isOuter = index % 2 == 0
            let radiusScale: CGFloat = isOuter ? 1 : ratio
            let point = CGPoint(
                x: center.x + a * radiusScale * cos(angle),
                y: center.y + b * radiusScale * sin(angle)
            )
            anchors.append(Anchor(corner: point))
        }

        return VectorPath(subpath: Subpath(anchors: anchors, isClosed: true))
    }
}

extension CGRect {
    /// `true`, wenn Ursprung und Grösse durchweg endliche Zahlen sind.
    var isFiniteRect: Bool {
        origin.x.isFinite && origin.y.isFinite
            && size.width.isFinite && size.height.isFinite
    }
}
