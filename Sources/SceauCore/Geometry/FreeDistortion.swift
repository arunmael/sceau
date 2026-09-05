import CoreGraphics

/// Vier unabhängig bewegliche Zielpunkte einer freien Verzerrung.
///
/// Die feste Reihenfolge entspricht der Konturrichtung der Grundformen und
/// verhindert, dass Aufrufer die Zuordnung zum Einheitsquadrat selbst führen
/// müssen.
public struct QuadCorners: Equatable, Sendable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint

    public init(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// Übernimmt die unverzerrten Rahmenecken als stabilen Ausgangszustand,
    /// damit eine einzelne bewegte Ecke tatsächlich nur ihren Anteil verändert.
    public init(rect: CGRect) {
        self.init(
            topLeft: CGPoint(x: rect.minX, y: rect.minY),
            topRight: CGPoint(x: rect.maxX, y: rect.minY),
            bottomRight: CGPoint(x: rect.maxX, y: rect.maxY),
            bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        )
    }
}

/// Freies Verziehen von Punkten und Pfaden über vier unabhängige Eckpunkte.
///
/// Bilineare Interpolation erlaubt auch Vierecke, die nicht durch eine affine
/// Matrix darstellbar sind, und bildet dadurch jede Ecke unabhängig ab.
public enum FreeDistortion {

    /// Bildet einen Punkt aus dem Quellrahmen auf das Zielviereck ab.
    ///
    /// Koordinaten ausserhalb des Rahmens werden bewusst extrapoliert, damit
    /// aussenliegende Bézier-Griffe der verzerrten Kontur weiter folgen.
    public static func warp(
        _ point: CGPoint,
        in sourceRect: CGRect,
        to corners: QuadCorners
    ) -> CGPoint {
        guard sourceRect.width > 0,
              sourceRect.height > 0,
              sourceRect.isFiniteRect else {
            return point
        }

        let u = (point.x - sourceRect.minX) / sourceRect.width
        let v = (point.y - sourceRect.minY) / sourceRect.height
        let topLeftWeight = (1 - u) * (1 - v)
        let topRightWeight = u * (1 - v)
        let bottomRightWeight = u * v
        let bottomLeftWeight = (1 - u) * v

        return CGPoint(
            x: topLeftWeight * corners.topLeft.x
                + topRightWeight * corners.topRight.x
                + bottomRightWeight * corners.bottomRight.x
                + bottomLeftWeight * corners.bottomLeft.x,
            y: topLeftWeight * corners.topLeft.y
                + topRightWeight * corners.topRight.y
                + bottomRightWeight * corners.bottomRight.y
                + bottomLeftWeight * corners.bottomLeft.y
        )
    }

    /// Verzieht sämtliche Pfadkoordinaten, ohne Konturaufbau oder
    /// Griffsemantik zu verändern.
    public static func warped(
        _ path: VectorPath,
        from sourceRect: CGRect,
        to corners: QuadCorners
    ) -> VectorPath {
        VectorPath(subpaths: path.subpaths.map { subpath in
            Subpath(
                anchors: subpath.anchors.map { anchor in
                    Anchor(
                        point: warp(anchor.point, in: sourceRect, to: corners),
                        controlIn: warp(anchor.controlIn, in: sourceRect, to: corners),
                        controlOut: warp(anchor.controlOut, in: sourceRect, to: corners),
                        style: anchor.style
                    )
                },
                isClosed: subpath.isClosed
            )
        })
    }
}
