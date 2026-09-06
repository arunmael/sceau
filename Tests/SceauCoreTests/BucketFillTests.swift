import CoreGraphics
import Testing

@testable import SceauCore

@Suite("BucketFill — Fläche innerhalb einer Abgrenzung finden")
struct BucketFillTests {

    private func rectangle(_ frame: CGRect) -> BucketFill.Boundary {
        BucketFill.Boundary(path: ShapeGeometry.path(for: .rectangle(frame: frame, cornerRadius: 0)), fillRule: .winding)
    }

    @Test("Eine einzelne Kontur um den Punkt liefert genau diese Kontur")
    func singleBoundaryReturnsItself() throws {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let region = try BucketFill.region(at: CGPoint(x: 50, y: 50), boundaries: [rectangle(frame)])
        #expect(region.bounds == frame)
    }

    @Test("Klick ausserhalb jeder Kontur wirft, statt stumm nichts zu tun")
    func pointOutsideEveryBoundaryThrows() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(throws: BucketFill.Error.noEnclosingBoundary) {
            try BucketFill.region(at: CGPoint(x: 500, y: 500), boundaries: [rectangle(frame)])
        }
    }

    @Test("Klick in der Überlappung zweier Rechtecke liefert nur die Schnittmenge")
    func overlapClickReturnsIntersection() throws {
        let a = rectangle(CGRect(x: 0, y: 0, width: 60, height: 60))
        let b = rectangle(CGRect(x: 30, y: 0, width: 60, height: 60))
        // (40, 30) liegt im Überlapp beider Rechtecke.
        let region = try BucketFill.region(at: CGPoint(x: 40, y: 30), boundaries: [a, b])
        #expect(region.bounds == CGRect(x: 30, y: 0, width: 30, height: 60))
    }

    @Test("Klick im Alleinbereich von A schneidet den Überlapp mit B heraus")
    func exclusiveAreaClickSubtractsOverlap() throws {
        let a = rectangle(CGRect(x: 0, y: 0, width: 60, height: 60))
        let b = rectangle(CGRect(x: 30, y: 0, width: 60, height: 60))
        // (10, 30) liegt nur in A, nicht in B.
        let region = try BucketFill.region(at: CGPoint(x: 10, y: 30), boundaries: [a, b])
        #expect(region.bounds == CGRect(x: 0, y: 0, width: 30, height: 60))
        // Der Überlapp mit B darf nicht mehr enthalten sein.
        #expect(!region.cgPath.contains(CGPoint(x: 40, y: 30)))
    }

    @Test("Eine dritte, unbeteiligte Kontur ohne Überlapp bleibt ohne Wirkung")
    func unrelatedDisjointBoundaryHasNoEffect() throws {
        let a = rectangle(CGRect(x: 0, y: 0, width: 60, height: 60))
        let farAway = rectangle(CGRect(x: 1000, y: 1000, width: 10, height: 10))
        let region = try BucketFill.region(at: CGPoint(x: 30, y: 30), boundaries: [a, farAway])
        #expect(region.bounds == CGRect(x: 0, y: 0, width: 60, height: 60))
    }

    @Test("Ein Loch (evenOdd) an der Klickstelle liefert keine Fläche")
    func evenOddHoleAtClickPointThrows() {
        // Aussenrechteck mit einem Loch in der Mitte, evenOdd-Füllregel —
        // der Klickpunkt liegt exakt im Loch, ist also nicht "gefüllt",
        // obwohl er innerhalb des äusseren Rahmens liegt.
        let outer = Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)
        ])
        let hole = Subpath(closedPolygon: [
            CGPoint(x: 40, y: 40), CGPoint(x: 60, y: 40),
            CGPoint(x: 60, y: 60), CGPoint(x: 40, y: 60)
        ])
        let donut = BucketFill.Boundary(path: VectorPath(subpaths: [outer, hole]), fillRule: .evenOdd)

        #expect(throws: BucketFill.Error.noEnclosingBoundary) {
            try BucketFill.region(at: CGPoint(x: 50, y: 50), boundaries: [donut])
        }
    }
}
