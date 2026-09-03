import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("Anker einfügen und entfernen")
struct AnchorInsertionTests {

    /// Fläche über den abgeflachten Pfad — dient als Formvergleich.
    private func area(of path: VectorPath) -> Double {
        var total = 0.0
        for ring in Flattener.polygons(of: path, tolerance: 0.01) {
            var sum = 0.0
            for index in ring.indices {
                let a = ring[index]
                let b = ring[(index + 1) % ring.count]
                sum += Double(a.x * b.y - b.x * a.y)
            }
            total += sum / 2
        }
        return abs(total)
    }

    /// Ein Kreis aus vier Kappa-Bögen.
    private func circle() -> VectorPath {
        ShapeGeometry.path(for: .ellipse(frame: CGRect(x: 0, y: 0, width: 100, height: 100)))
    }

    @Test("Eine Gerade in der Mitte zu teilen ergibt den Mittelpunkt")
    func splittingLineGivesMidpoint() {
        let segment = CubicSegment(line: CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0))
        let (first, second) = segment.split(at: 0.5)

        #expect(first.end == CGPoint(x: 50, y: 0))
        #expect(second.start == CGPoint(x: 50, y: 0))
        #expect(first.start == segment.start)
        #expect(second.end == segment.end)
    }

    @Test("Die Teilung trifft exakt den Kurvenpunkt bei t")
    func splitMeetsCurveAtT() {
        let segment = CubicSegment(
            start: CGPoint(x: 0, y: 0),
            control1: CGPoint(x: 0, y: 100),
            control2: CGPoint(x: 100, y: 100),
            end: CGPoint(x: 100, y: 0)
        )
        for t in [0.25, 0.5, 0.75] {
            let (first, _) = segment.split(at: CGFloat(t))
            let expected = segment.point(at: CGFloat(t))
            #expect(abs(first.end.x - expected.x) < 0.000001)
            #expect(abs(first.end.y - expected.y) < 0.000001)
        }
    }

    @Test("Ein eingefügter Anker verändert die Form des Kreises nicht")
    func insertingAnchorKeepsShape() {
        let original = circle()
        let before = area(of: original)

        let expanded = original.insertingAnchor(at: AnchorAddress(subpath: 0, index: 0), t: 0.4)

        #expect(expanded.subpaths[0].anchors.count == original.subpaths[0].anchors.count + 1)
        let after = area(of: expanded)
        // Der Kreis darf sich durch das Einfügen nicht messbar verformen.
        #expect(abs(after - before) < 0.5, "vorher \(before), nachher \(after)")
    }

    @Test("Einfügen auf dem Schlusssegment eines geschlossenen Pfades")
    func insertingOnClosingSegment() {
        let triangle = VectorPath(subpath: Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100)
        ]))
        // Index 2 ist das Segment vom letzten Anker zurück zum ersten.
        let expanded = triangle.insertingAnchor(at: AnchorAddress(subpath: 0, index: 2), t: 0.5)

        #expect(expanded.subpaths[0].anchors.count == 4)
        #expect(expanded.subpaths[0].anchors[3].point == CGPoint(x: 50, y: 50))
        #expect(abs(area(of: expanded) - area(of: triangle)) < 0.01)
    }

    @Test("Nächstgelegenes Segment wird gefunden")
    func findsNearestSegment() throws {
        let square = VectorPath(subpath: Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100)
        ]))

        // Dicht an der Mitte der oberen Kante.
        let hit = try #require(square.closestSegment(to: CGPoint(x: 50, y: 2), tolerance: 6))
        #expect(hit.address.index == 0)
        #expect(abs(hit.t - 0.5) < 0.05)

        // Mitten im Inneren liegt nichts in Reichweite.
        #expect(square.closestSegment(to: CGPoint(x: 50, y: 50), tolerance: 6) == nil)
    }

    @Test("Anker entfernen verkleinert den Pfad")
    func removingAnchor() {
        let square = VectorPath(subpath: Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100)
        ]))
        let reduced = square.removingAnchor(at: AnchorAddress(subpath: 0, index: 1))

        #expect(reduced.subpaths[0].anchors.count == 3)
        #expect(reduced.subpaths[0].anchors[1].point == CGPoint(x: 100, y: 100))
    }

    @Test("Der letzte verbleibende Teilpfad wird nicht unter zwei Anker gekürzt")
    func removingKeepsMinimumAnchors() {
        let line = VectorPath(subpath: Subpath(
            anchors: [Anchor(corner: .zero), Anchor(corner: CGPoint(x: 10, y: 0))],
            isClosed: false
        ))
        #expect(line.removingAnchor(at: AnchorAddress(subpath: 0, index: 0)) == line)
    }

    @Test("Ungültige Adressen bleiben wirkungslos")
    func invalidAddressesAreSafe() {
        let path = circle()
        #expect(path.insertingAnchor(at: AnchorAddress(subpath: 5, index: 0), t: 0.5) == path)
        #expect(path.insertingAnchor(at: AnchorAddress(subpath: 0, index: 99), t: 0.5) == path)
        #expect(path.removingAnchor(at: AnchorAddress(subpath: 5, index: 0)) == path)
    }

    @Test("t ausserhalb von 0 bis 1 wird begrenzt statt zu entgleisen")
    func tIsClamped() {
        let path = circle()
        let low = path.insertingAnchor(at: AnchorAddress(subpath: 0, index: 0), t: -3)
        let high = path.insertingAnchor(at: AnchorAddress(subpath: 0, index: 0), t: 7)

        #expect(low.subpaths[0].anchors.count == path.subpaths[0].anchors.count + 1)
        #expect(high.subpaths[0].anchors.count == path.subpaths[0].anchors.count + 1)
        let allFinite = (low.allAnchors + high.allAnchors).allSatisfy {
            $0.point.x.isFinite && $0.point.y.isFinite
        }
        #expect(allFinite)
    }
}
