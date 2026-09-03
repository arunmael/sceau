import CoreGraphics

/// Welcher Teil eines Ankers angefasst wurde.
public enum AnchorHandle: Equatable, Sendable {
    case point
    case controlIn
    case controlOut
}

/// Die Stelle eines Ankers innerhalb eines Pfades.
public struct AnchorAddress: Equatable, Sendable {
    public var subpath: Int
    public var index: Int

    public init(subpath: Int, index: Int) {
        self.subpath = subpath
        self.index = index
    }
}

public extension VectorPath {

    /// Sucht den Anker oder Griff unter einem Punkt.
    ///
    /// Griffe haben Vorrang vor dem Anker selbst: Sie liegen oft dicht daneben,
    /// und wer einen Griff anvisiert, will ihn auch treffen — den Anker
    /// erwischt man notfalls an einer anderen Stelle wieder.
    func hitTestAnchor(
        at point: CGPoint,
        tolerance: CGFloat
    ) -> (address: AnchorAddress, handle: AnchorHandle)? {
        var bestHandle: (AnchorAddress, AnchorHandle, CGFloat)?
        var bestPoint: (AnchorAddress, AnchorHandle, CGFloat)?

        for (subpathIndex, subpath) in subpaths.enumerated() {
            for (anchorIndex, anchor) in subpath.anchors.enumerated() {
                let address = AnchorAddress(subpath: subpathIndex, index: anchorIndex)

                // Ein Griff, der auf seinem Anker liegt, hat keine Kurvenwirkung
                // und ist damit auch nicht anfassbar.
                if !anchor.hasStraightIn {
                    consider(anchor.controlIn, address, .controlIn, &bestHandle)
                }
                if !anchor.hasStraightOut {
                    consider(anchor.controlOut, address, .controlOut, &bestHandle)
                }
                consider(anchor.point, address, .point, &bestPoint)
            }
        }

        func distance(_ candidate: (AnchorAddress, AnchorHandle, CGFloat)?) -> CGFloat {
            candidate?.2 ?? .greatestFiniteMagnitude
        }

        func consider(
            _ candidate: CGPoint,
            _ address: AnchorAddress,
            _ handle: AnchorHandle,
            _ best: inout (AnchorAddress, AnchorHandle, CGFloat)?
        ) {
            let d = hypot(candidate.x - point.x, candidate.y - point.y)
            guard d <= tolerance else { return }
            if d < distance(best) {
                best = (address, handle, d)
            }
        }

        if let hit = bestHandle ?? bestPoint {
            return (hit.0, hit.1)
        }
        return nil
    }

    /// Bewegt einen Anker oder einen seiner Griffe.
    ///
    /// Die Semantik aus ``AnchorStyle`` wird dabei eingehalten: Bei
    /// `.symmetric` wird der Gegengriff gespiegelt, bei `.smooth` nur
    /// mitgedreht (seine Länge bleibt), bei `.corner` bleibt er unberührt.
    /// Ein ungültiger Zugriff lässt den Pfad unverändert, statt abzustürzen.
    func movingHandle(
        _ handle: AnchorHandle,
        at address: AnchorAddress,
        to point: CGPoint
    ) -> VectorPath {
        guard subpaths.indices.contains(address.subpath),
              subpaths[address.subpath].anchors.indices.contains(address.index)
        else { return self }

        var result = self
        var anchor = result.subpaths[address.subpath].anchors[address.index]

        switch handle {
        case .point:
            // Der Anker nimmt seine Griffe mit, sonst verformte sich die Kurve
            // beim blossen Verschieben.
            let delta = CGVector(dx: point.x - anchor.point.x, dy: point.y - anchor.point.y)
            anchor = anchor.moved(by: delta)

        case .controlOut:
            anchor.controlOut = point
            anchor.controlIn = counterpart(of: point, opposite: anchor.controlIn, anchor: anchor)

        case .controlIn:
            anchor.controlIn = point
            anchor.controlOut = counterpart(of: point, opposite: anchor.controlOut, anchor: anchor)
        }

        result.subpaths[address.subpath].anchors[address.index] = anchor
        return result
    }

    /// Wohin der jeweils andere Griff rückt, wenn einer bewegt wird.
    private func counterpart(of moved: CGPoint, opposite: CGPoint, anchor: Anchor) -> CGPoint {
        let base = anchor.point

        switch anchor.style {
        case .corner:
            return opposite

        case .symmetric:
            return CGPoint(x: 2 * base.x - moved.x, y: 2 * base.y - moved.y)

        case .smooth:
            let length = hypot(opposite.x - base.x, opposite.y - base.y)
            let dx = moved.x - base.x
            let dy = moved.y - base.y
            let movedLength = hypot(dx, dy)
            // Ohne Richtung gibt es nichts zu drehen.
            guard movedLength > 0 else { return opposite }
            return CGPoint(
                x: base.x - dx / movedLength * length,
                y: base.y - dy / movedLength * length
            )
        }
    }
}
