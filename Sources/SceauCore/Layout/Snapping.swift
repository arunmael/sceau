import CoreGraphics

/// Eine Hilfslinie, die anzeigt, woran gerade eingerastet wurde.
public struct SnapGuide: Equatable, Sendable {
    public enum Orientation: Sendable { case vertical, horizontal }
    public var orientation: Orientation
    /// x bei senkrechter, y bei waagrechter Linie.
    public var position: CGFloat
    /// Bereich, über den die Linie gezeichnet werden soll (von…bis auf der anderen Achse).
    public var start: CGFloat
    public var end: CGFloat
}

public struct SnapResult: Equatable, Sendable {
    /// Die Verschiebung, die auf die Eingabe anzuwenden ist.
    public var offset: CGVector
    public var guides: [SnapGuide]
    public static var none: SnapResult { .init(offset: .zero, guides: []) }
}

public struct SnapSettings: Sendable {
    /// Rasterweite in Punkt. `nil` schaltet das Raster ab.
    public var gridSize: CGFloat?
    /// Ob an Kanten und Mitten anderer Objekte eingerastet wird.
    public var snapsToObjects: Bool
    /// Maximaler Abstand in **Dokumentpunkten**, bis zu dem eingerastet wird.
    public var threshold: CGFloat

    public init(gridSize: CGFloat? = 8, snapsToObjects: Bool = true, threshold: CGFloat = 6) {
        self.gridSize = gridSize
        self.snapsToObjects = snapsToObjects
        self.threshold = threshold
    }
}

/// Einrasten beim Ziehen von Rahmen und Punkten.
///
/// Prüft pro Achse unabhängig, ob einer der drei Bezugswerte (Anfang, Mitte,
/// Ende) nahe genug an einem Kandidaten liegt, und liefert dafür eine
/// Verschiebung statt selbst am Dokument zu rühren — Aufrufer entscheiden, wie
/// die Verschiebung auf einen Knoten wirkt.
public enum Snapper {

    /// Rastet einen bewegten Rahmen ein.
    public static func snap(
        rect: CGRect,
        to targets: [CGRect],
        within artboard: CGRect,
        settings: SnapSettings
    ) -> SnapResult {
        let references = referenceRects(targets: targets, artboard: artboard, settings: settings)

        let x = snapAxis(
            movedValues: [rect.minX, rect.midX, rect.maxX],
            references: references.map { AxisValues(min: $0.minX, mid: $0.midX, max: $0.maxX, rect: $0) },
            gridSize: settings.gridSize,
            threshold: settings.threshold
        )
        let y = snapAxis(
            movedValues: [rect.minY, rect.midY, rect.maxY],
            references: references.map { AxisValues(min: $0.minY, mid: $0.midY, max: $0.maxY, rect: $0) },
            gridSize: settings.gridSize,
            threshold: settings.threshold
        )

        guard x.matched || y.matched else { return .none }

        let moved = rect.offsetBy(dx: x.offset, dy: y.offset)
        var guides: [SnapGuide] = []

        if x.matched, let target = x.guideTarget {
            guides.append(SnapGuide(
                orientation: .vertical,
                position: x.value,
                start: min(moved.minY, target.minY),
                end: max(moved.maxY, target.maxY)
            ))
        }
        if y.matched, let target = y.guideTarget {
            guides.append(SnapGuide(
                orientation: .horizontal,
                position: y.value,
                start: min(moved.minX, target.minX),
                end: max(moved.maxX, target.maxX)
            ))
        }

        return SnapResult(offset: CGVector(dx: x.offset, dy: y.offset), guides: guides)
    }

    /// Rastet einen einzelnen Punkt ein (Zeichenstift, Ankerpunkte).
    public static func snap(
        point: CGPoint,
        to targets: [CGRect],
        within artboard: CGRect,
        settings: SnapSettings
    ) -> SnapResult {
        let references = referenceRects(targets: targets, artboard: artboard, settings: settings)

        let x = snapAxis(
            movedValues: [point.x],
            references: references.map { AxisValues(min: $0.minX, mid: $0.midX, max: $0.maxX, rect: $0) },
            gridSize: settings.gridSize,
            threshold: settings.threshold
        )
        let y = snapAxis(
            movedValues: [point.y],
            references: references.map { AxisValues(min: $0.minY, mid: $0.midY, max: $0.maxY, rect: $0) },
            gridSize: settings.gridSize,
            threshold: settings.threshold
        )

        guard x.matched || y.matched else { return .none }

        let moved = CGPoint(x: point.x + x.offset, y: point.y + y.offset)
        var guides: [SnapGuide] = []

        if x.matched, let target = x.guideTarget {
            guides.append(SnapGuide(
                orientation: .vertical,
                position: x.value,
                start: min(moved.y, target.minY),
                end: max(moved.y, target.maxY)
            ))
        }
        if y.matched, let target = y.guideTarget {
            guides.append(SnapGuide(
                orientation: .horizontal,
                position: y.value,
                start: min(moved.x, target.minX),
                end: max(moved.x, target.maxX)
            ))
        }

        return SnapResult(offset: CGVector(dx: x.offset, dy: y.offset), guides: guides)
    }

    /// Die Zeichenfläche zählt immer mit — sie ist kein "anderes Objekt", das
    /// sich über `snapsToObjects` abschalten liesse, sondern der feste Bezug
    /// eines Dokuments (z.B. um ein Logo zu zentrieren).
    private static func referenceRects(targets: [CGRect], artboard: CGRect, settings: SnapSettings) -> [CGRect] {
        (settings.snapsToObjects ? targets : []) + [artboard]
    }

    private struct AxisValues {
        var min: CGFloat
        var mid: CGFloat
        var max: CGFloat
        var rect: CGRect
    }

    private struct AxisSnap {
        var matched = false
        var offset: CGFloat = 0
        var value: CGFloat = 0
        var guideTarget: CGRect?
    }

    /// Sucht pro Achse den nächstliegenden Kandidaten. Kanten und Mitten von
    /// Objekten haben Vorrang vor dem Raster — wird dort etwas gefunden, wird
    /// das Raster gar nicht erst geprüft, denn an einer echten Kante
    /// auszurichten ist fast immer die Absicht.
    private static func snapAxis(
        movedValues: [CGFloat],
        references: [AxisValues],
        gridSize: CGFloat?,
        threshold: CGFloat
    ) -> AxisSnap {
        var best: (distance: CGFloat, offset: CGFloat, value: CGFloat, rect: CGRect)?

        for moved in movedValues {
            for reference in references {
                for targetValue in [reference.min, reference.mid, reference.max] {
                    let diff = targetValue - moved
                    let distance = abs(diff)
                    guard distance <= threshold else { continue }
                    if best == nil || distance < best!.distance {
                        best = (distance, diff, targetValue, reference.rect)
                    }
                }
            }
        }

        if let best {
            return AxisSnap(matched: true, offset: best.offset, value: best.value, guideTarget: best.rect)
        }

        guard let gridSize, gridSize > 0 else { return AxisSnap() }

        var bestGrid: (distance: CGFloat, offset: CGFloat, value: CGFloat)?
        for moved in movedValues {
            let nearest = (moved / gridSize).rounded() * gridSize
            let diff = nearest - moved
            let distance = abs(diff)
            guard distance <= threshold else { continue }
            if bestGrid == nil || distance < bestGrid!.distance {
                bestGrid = (distance, diff, nearest)
            }
        }

        guard let bestGrid else { return AxisSnap() }
        return AxisSnap(matched: true, offset: bestGrid.offset, value: bestGrid.value, guideTarget: nil)
    }
}
