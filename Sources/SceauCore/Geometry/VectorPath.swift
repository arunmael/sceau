import CoreGraphics

/// Ein zusammenhängender Teilpfad aus Ankerpunkten, offen oder geschlossen.
public struct Subpath: Equatable, Sendable, Codable {
    public var anchors: [Anchor]
    public var isClosed: Bool

    public init(anchors: [Anchor], isClosed: Bool) {
        self.anchors = anchors
        self.isClosed = isClosed
    }

    /// Geschlossener Teilpfad aus lauter Eckpunkten — der übliche Weg, ein
    /// Polygon (etwa das Ergebnis einer booleschen Operation) einzulesen.
    public init(closedPolygon points: [CGPoint]) {
        self.init(anchors: points.map(Anchor.init(corner:)), isClosed: true)
    }

    /// Die Bézier-Segmente dieses Teilpfads.
    ///
    /// Bei `isClosed == true` enthält das Ergebnis zusätzlich das schliessende
    /// Segment vom letzten zurück zum ersten Anker.
    public var segments: [CubicSegment] {
        guard anchors.count >= 2 else { return [] }
        var result: [CubicSegment] = []
        result.reserveCapacity(isClosed ? anchors.count : anchors.count - 1)

        for index in 0..<(anchors.count - 1) {
            result.append(Self.segment(from: anchors[index], to: anchors[index + 1]))
        }
        if isClosed, let first = anchors.first, let last = anchors.last {
            result.append(Self.segment(from: last, to: first))
        }
        return result
    }

    private static func segment(from a: Anchor, to b: Anchor) -> CubicSegment {
        // Der ausgehende Griff von `a` und der eingehende Griff von `b` spannen
        // das Segment auf. Liegen beide auf ihrem Anker, ist es exakt eine Gerade.
        CubicSegment(
            start: a.point,
            control1: a.controlOut,
            control2: b.controlIn,
            end: b.point
        )
    }
}

/// Die editierbare Vektor-Repräsentation eines Pfades — das zentrale
/// Geometrie-Modell der App.
///
/// Bewusst **nicht** `CGPath`: `CGPath` ist unveränderlich und gibt einzelne
/// Ankerpunkte nicht wieder her, taugt also nicht fürs Live-Editing. Aus dieser
/// Repräsentation wird pro Frame ein `CGPath` fürs Rendern gebaut (``cgPath``).
///
/// Mehrere ``Subpath``-Elemente bilden zusammen eine Form mit Löchern (etwa der
/// Buchstabe „O" oder das Ergebnis einer Subtraktion). Welche Teilpfade als Loch
/// gelten, entscheidet die Füllregel in ``Style/fillRule``.
public struct VectorPath: Equatable, Sendable, Codable {
    public var subpaths: [Subpath]

    public init(subpaths: [Subpath] = []) {
        self.subpaths = subpaths
    }

    public init(subpath: Subpath) {
        self.init(subpaths: [subpath])
    }

    public var isEmpty: Bool {
        subpaths.allSatisfy { $0.anchors.isEmpty }
    }

    /// Alle Ankerpunkte über sämtliche Teilpfade hinweg.
    public var allAnchors: [Anchor] {
        subpaths.flatMap(\.anchors)
    }

    /// Der exakte, enge Hüllrahmen — inklusive Kurvenausbuchtungen.
    ///
    /// Nutzt `CGPath.boundingBoxOfPath`, das die Extrema der Bézierkurven
    /// berücksichtigt (im Gegensatz zum Hüllrahmen der blossen Kontrollpunkte).
    /// Für einen leeren Pfad ist das Ergebnis `.null`.
    public var bounds: CGRect {
        let box = cgPath.boundingBoxOfPath
        return box.isInfinite ? .null : box
    }

    /// Baut die unveränderliche `CGPath`-Darstellung fürs Rendern und für
    /// Treffertests.
    public var cgPath: CGPath {
        let path = CGMutablePath()
        for subpath in subpaths {
            guard let first = subpath.anchors.first else { continue }
            path.move(to: first.point)

            for segment in subpath.segments {
                if segment.isLine {
                    path.addLine(to: segment.end)
                } else {
                    path.addCurve(
                        to: segment.end,
                        control1: segment.control1,
                        control2: segment.control2
                    )
                }
            }
            if subpath.isClosed {
                path.closeSubpath()
            }
        }
        return path
    }

    /// Verschiebt sämtliche Anker und Griffe.
    public func moved(by delta: CGVector) -> VectorPath {
        VectorPath(subpaths: subpaths.map { subpath in
            Subpath(anchors: subpath.anchors.map { $0.moved(by: delta) }, isClosed: subpath.isClosed)
        })
    }

    /// Wendet eine affine Transformation auf Anker und Griffe an.
    public func applying(_ transform: CGAffineTransform) -> VectorPath {
        VectorPath(subpaths: subpaths.map { subpath in
            Subpath(
                anchors: subpath.anchors.map { anchor in
                    Anchor(
                        point: anchor.point.applying(transform),
                        controlIn: anchor.controlIn.applying(transform),
                        controlOut: anchor.controlOut.applying(transform),
                        style: anchor.style
                    )
                },
                isClosed: subpath.isClosed
            )
        })
    }
}
