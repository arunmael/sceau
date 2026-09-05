import CoreGraphics
import Testing

@testable import SceauCore

@Suite("FreeDistortion — freies Verziehen über vier unabhängige Eckpunkte")
struct FreeDistortionTests {

    private let frame = CGRect(x: 0, y: 0, width: 100, height: 50)

    @Test("Unveränderte Eckpunkte (Identität) lassen jeden Punkt unverändert")
    func identityCornersLeavePointsUnchanged() {
        let corners = QuadCorners(rect: frame)
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50), CGPoint(x: 37, y: 12)] {
            let warped = FreeDistortion.warp(point, in: frame, to: corners)
            #expect(abs(warped.x - point.x) < 0.001)
            #expect(abs(warped.y - point.y) < 0.001)
        }
    }

    @Test("Alle vier Ecken gleich verschoben wirkt wie eine reine Verschiebung")
    func translatingAllCornersTranslatesEveryPoint() {
        let delta = CGVector(dx: 10, dy: -5)
        let corners = QuadCorners(
            topLeft: CGPoint(x: frame.minX + delta.dx, y: frame.minY + delta.dy),
            topRight: CGPoint(x: frame.maxX + delta.dx, y: frame.minY + delta.dy),
            bottomRight: CGPoint(x: frame.maxX + delta.dx, y: frame.maxY + delta.dy),
            bottomLeft: CGPoint(x: frame.minX + delta.dx, y: frame.maxY + delta.dy)
        )
        let point = CGPoint(x: 40, y: 20)
        let warped = FreeDistortion.warp(point, in: frame, to: corners)
        #expect(abs(warped.x - (point.x + delta.dx)) < 0.001)
        #expect(abs(warped.y - (point.y + delta.dy)) < 0.001)
    }

    @Test("Nur eine Ecke verschieben lässt die drei anderen Referenzpunkte an ihrem Platz")
    func movingOneCornerLeavesTheOthersAtTheirOwnCorner() {
        let movedBottomRight = CGPoint(x: 200, y: 120)
        let corners = QuadCorners(
            topLeft: CGPoint(x: frame.minX, y: frame.minY),
            topRight: CGPoint(x: frame.maxX, y: frame.minY),
            bottomRight: movedBottomRight,
            bottomLeft: CGPoint(x: frame.minX, y: frame.maxY)
        )

        let topLeft = FreeDistortion.warp(CGPoint(x: frame.minX, y: frame.minY), in: frame, to: corners)
        let topRight = FreeDistortion.warp(CGPoint(x: frame.maxX, y: frame.minY), in: frame, to: corners)
        let bottomLeft = FreeDistortion.warp(CGPoint(x: frame.minX, y: frame.maxY), in: frame, to: corners)
        let bottomRight = FreeDistortion.warp(CGPoint(x: frame.maxX, y: frame.maxY), in: frame, to: corners)

        #expect(abs(topLeft.x - frame.minX) < 0.001 && abs(topLeft.y - frame.minY) < 0.001)
        #expect(abs(topRight.x - frame.maxX) < 0.001 && abs(topRight.y - frame.minY) < 0.001)
        #expect(abs(bottomLeft.x - frame.minX) < 0.001 && abs(bottomLeft.y - frame.maxY) < 0.001)
        #expect(abs(bottomRight.x - movedBottomRight.x) < 0.001 && abs(bottomRight.y - movedBottomRight.y) < 0.001)
    }

    @Test("Entarteter Rahmen (Breite oder Höhe 0) liefert den Punkt unverändert statt NaN")
    func degenerateFrameReturnsPointUnchanged() {
        let degenerate = CGRect(x: 0, y: 0, width: 0, height: 40)
        let corners = QuadCorners(
            topLeft: .zero, topRight: CGPoint(x: 50, y: 0),
            bottomRight: CGPoint(x: 50, y: 40), bottomLeft: CGPoint(x: 0, y: 40)
        )
        let point = CGPoint(x: 0, y: 20)
        let warped = FreeDistortion.warp(point, in: degenerate, to: corners)
        #expect(warped.x.isFinite && warped.y.isFinite)
        #expect(abs(warped.x - point.x) < 0.001)
        #expect(abs(warped.y - point.y) < 0.001)
    }

    @Test("Ein Rechteckpfad verzogen: die vier Eckanker landen exakt auf den neuen Eckpunkten")
    func warpedRectanglePathLandsOnNewCorners() {
        let path = ShapeGeometry.path(for: .rectangle(frame: frame, cornerRadius: 0))
        let corners = QuadCorners(
            topLeft: CGPoint(x: -10, y: -10),
            topRight: CGPoint(x: 120, y: 0),
            bottomRight: CGPoint(x: 100, y: 60),
            bottomLeft: CGPoint(x: 5, y: 55)
        )
        let warped = FreeDistortion.warped(path, from: frame, to: corners)

        #expect(warped.subpaths.count == 1)
        let anchors = warped.subpaths[0].anchors
        #expect(anchors.count == 4)
        #expect(warped.subpaths[0].isClosed)

        // Reihenfolge aus ShapeGeometry: links-oben, rechts-oben, rechts-unten, links-unten.
        #expect(abs(anchors[0].point.x - corners.topLeft.x) < 0.001)
        #expect(abs(anchors[0].point.y - corners.topLeft.y) < 0.001)
        #expect(abs(anchors[2].point.x - corners.bottomRight.x) < 0.001)
        #expect(abs(anchors[2].point.y - corners.bottomRight.y) < 0.001)
    }
}
