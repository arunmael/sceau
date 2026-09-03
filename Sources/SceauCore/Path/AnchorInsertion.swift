import CoreGraphics

public extension CubicSegment {

    /// Teilt das Segment bei `t` in zwei Segmente, die zusammen exakt dieselbe
    /// Kurve beschreiben.
    ///
    /// De-Casteljau-Konstruktion: Sie liefert die neuen Kontrollpunkte gleich
    /// mit, weshalb die Form beim Einfügen eines Ankers unverändert bleibt —
    /// ein blosses Einhängen des Kurvenpunkts würde sie dagegen verziehen.
    func split(at t: CGFloat) -> (CubicSegment, CubicSegment) {
        let clamped = Swift.min(1, Swift.max(0, t))

        func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * clamped, y: a.y + (b.y - a.y) * clamped)
        }

        let ab = lerp(start, control1)
        let bc = lerp(control1, control2)
        let cd = lerp(control2, end)
        let abbc = lerp(ab, bc)
        let bccd = lerp(bc, cd)
        let middle = lerp(abbc, bccd)

        return (
            CubicSegment(start: start, control1: ab, control2: abbc, end: middle),
            CubicSegment(start: middle, control1: bccd, control2: cd, end: end)
        )
    }
}

public extension VectorPath {

    /// Das Segment, das einem Punkt am nächsten liegt.
    ///
    /// - Returns: Teilpfad und Segmentindex, die Lage `t` darauf und der
    ///   Abstand — oder `nil`, wenn nichts innerhalb der Toleranz liegt.
    func closestSegment(
        to point: CGPoint,
        tolerance: CGFloat
    ) -> (address: AnchorAddress, t: CGFloat, distance: CGFloat)? {
        var best: (AnchorAddress, CGFloat, CGFloat)?

        for (subpathIndex, subpath) in subpaths.enumerated() {
            for (segmentIndex, segment) in subpath.segments.enumerated() {
                // Grobe Abtastung, danach eine kurze Verfeinerung um den besten
                // Wert. Das genügt für einen Mausklick und kommt ohne das
                // Lösen einer Gleichung fünften Grades aus.
                var bestT: CGFloat = 0
                var bestDistance = CGFloat.greatestFiniteMagnitude

                for step in 0...32 {
                    let t = CGFloat(step) / 32
                    let candidate = segment.point(at: t)
                    let distance = hypot(candidate.x - point.x, candidate.y - point.y)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestT = t
                    }
                }

                var window: CGFloat = 1.0 / 32
                for _ in 0..<12 {
                    for offset in [-window, window] {
                        let t = Swift.min(1, Swift.max(0, bestT + offset))
                        let candidate = segment.point(at: t)
                        let distance = hypot(candidate.x - point.x, candidate.y - point.y)
                        if distance < bestDistance {
                            bestDistance = distance
                            bestT = t
                        }
                    }
                    window /= 2
                }

                guard bestDistance <= tolerance else { continue }
                if bestDistance < (best?.2 ?? .greatestFiniteMagnitude) {
                    best = (AnchorAddress(subpath: subpathIndex, index: segmentIndex), bestT, bestDistance)
                }
            }
        }

        guard let best else { return nil }
        return (best.0, best.1, best.2)
    }

    /// Fügt auf dem angegebenen **Segment** einen Anker ein, ohne die Form zu
    /// verändern.
    ///
    /// `address.index` bezeichnet hier das Segment, nicht den Anker: Bei einem
    /// geschlossenen Teilpfad gibt es ein Segment mehr als Anker, nämlich das
    /// zurück zum Anfang.
    func insertingAnchor(at address: AnchorAddress, t: CGFloat) -> VectorPath {
        guard subpaths.indices.contains(address.subpath) else { return self }
        let subpath = subpaths[address.subpath]
        let segments = subpath.segments
        guard segments.indices.contains(address.index) else { return self }

        let (first, second) = segments[address.index].split(at: t)

        // Beim Schlusssegment eines geschlossenen Pfades ist der Nachbar wieder
        // der erste Anker, und der neue Anker gehört ans Ende.
        let startIndex = address.index
        let endIndex = (address.index + 1) % subpath.anchors.count

        var anchors = subpath.anchors
        guard anchors.indices.contains(startIndex), anchors.indices.contains(endIndex) else { return self }

        anchors[startIndex].controlOut = first.control1
        anchors[endIndex].controlIn = second.control2

        let inserted = Anchor(
            point: first.end,
            controlIn: first.control2,
            controlOut: second.control1,
            style: .smooth
        )
        anchors.insert(inserted, at: startIndex + 1)

        var result = self
        result.subpaths[address.subpath] = Subpath(anchors: anchors, isClosed: subpath.isClosed)
        return result
    }

    /// Entfernt einen Anker.
    ///
    /// Anders als beim Einfügen ändert sich die Form dabei zwangsläufig — der
    /// Kurvenverlauf hing ja an diesem Punkt. Unter zwei Anker wird ein
    /// Teilpfad nicht gekürzt; was dann bliebe, wäre kein Pfad mehr.
    func removingAnchor(at address: AnchorAddress) -> VectorPath {
        guard subpaths.indices.contains(address.subpath) else { return self }
        let subpath = subpaths[address.subpath]
        guard subpath.anchors.indices.contains(address.index) else { return self }
        guard subpath.anchors.count > 2 else { return self }

        var anchors = subpath.anchors
        anchors.remove(at: address.index)

        var result = self
        result.subpaths[address.subpath] = Subpath(anchors: anchors, isClosed: subpath.isClosed)
        return result
    }
}
