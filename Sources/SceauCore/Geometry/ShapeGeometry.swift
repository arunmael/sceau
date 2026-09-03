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

    // MARK: - Polygon

    private static func polygonPath(frame: CGRect, sides: Int) -> VectorPath {
        let count = max(3, sides)
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
        let count = max(3, points)
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
