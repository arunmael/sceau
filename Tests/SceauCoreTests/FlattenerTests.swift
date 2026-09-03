import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("Flattener — adaptive Abflachung")
struct FlattenerTests {

    /// Viertelkreisbogen von (100,0) nach (0,100) um den Ursprung, mit dem
    /// klassischen Kappa-Faktor für Kreisannäherung per kubischer Bézier.
    /// Der Bogen selbst weicht vom echten Kreis um höchstens ~0.0273 ab
    /// (bekannte Eigenschaft dieser Approximation) — das ist die Messlatte,
    /// an der die Genauigkeit des Flatteners hier geprüft wird.
    private static func quarterCircleArc(radius: CGFloat = 100) -> CubicSegment {
        let kappa: CGFloat = 0.5522847498307936
        return CubicSegment(
            start: CGPoint(x: radius, y: 0),
            control1: CGPoint(x: radius, y: radius * kappa),
            control2: CGPoint(x: radius * kappa, y: radius),
            end: CGPoint(x: 0, y: radius)
        )
    }

    @Test("Jeder abgeflachte Punkt eines Viertelkreisbogens liegt auf dem Kreis (±0.05)")
    func flattenedQuarterCircleStaysOnCircle() {
        let arc = Self.quarterCircleArc(radius: 100)
        let points = Flattener.flatten(arc, tolerance: 0.05)

        #expect(!points.isEmpty)

        let allOnCircle = points.allSatisfy { point in
            let distance = (point.x * point.x + point.y * point.y).squareRoot()
            return abs(distance - 100) <= 0.05
        }
        #expect(allOnCircle)
    }

    @Test("Kleinere Toleranz erzeugt mehr Punkte")
    func smallerToleranceProducesMorePoints() {
        let arc = Self.quarterCircleArc(radius: 100)
        let coarse = Flattener.flatten(arc, tolerance: 5.0)
        let fine = Flattener.flatten(arc, tolerance: 0.01)

        #expect(fine.count > coarse.count)
    }

    @Test("Gerade Segmente erzeugen genau einen Punkt")
    func straightSegmentProducesSinglePoint() {
        let line = CubicSegment(line: CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50))
        let points = Flattener.flatten(line, tolerance: 0.05)

        #expect(points.count == 1)
        #expect(points[0] == CGPoint(x: 100, y: 50))
    }

    @Test("Entartete Kurve (Kontrollpunkte weit ausserhalb) läuft nicht in Endlosrekursion")
    func degenerateCurveDoesNotRecurseForever() {
        // Start und Ende fallen zusammen, Kontrollpunkte weit weg — ein
        // klassischer Entartungsfall, der ohne Tiefenbegrenzung eine
        // Endlosrekursion auslösen könnte.
        let segment = CubicSegment(
            start: CGPoint(x: 0, y: 0),
            control1: CGPoint(x: 1_000_000, y: 0),
            control2: CGPoint(x: -1_000_000, y: 0),
            end: CGPoint(x: 0, y: 0)
        )
        let points = Flattener.flatten(segment, tolerance: 0.05)

        // Muss terminieren und darf keine absurde Punktzahl erzeugen.
        #expect(points.count < 1_000_000)
    }

    @Test("polygons(of:) liefert pro geschlossenem Teilpfad einen Ring ohne doppelten Schlusspunkt")
    func polygonsProducesClosedRingsWithoutDuplicateClosingPoint() {
        let subpath = Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100)
        ])
        let path = VectorPath(subpath: subpath)

        let rings = Flattener.polygons(of: path, tolerance: 0.05)

        #expect(rings.count == 1)
        #expect(rings[0].count == 4)
        #expect(rings[0].first == CGPoint(x: 0, y: 0))
    }

    @Test("polygons(of:) lässt entartete Ringe mit weniger als 3 Punkten weg")
    func polygonsDropsDegenerateRings() {
        let subpath = Subpath(
            anchors: [Anchor(corner: CGPoint(x: 0, y: 0)), Anchor(corner: CGPoint(x: 10, y: 0))],
            isClosed: true
        )
        let path = VectorPath(subpath: subpath)

        let rings = Flattener.polygons(of: path, tolerance: 0.05)
        #expect(rings.isEmpty)
    }
}
