import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("PenDraft — Zeichenstift")
struct PenDraftTests {

    @Test("Ein blosser Klick erzeugt einen Eckpunkt ohne Kurvenwirkung")
    func clickCreatesCornerAnchor() {
        var draft = PenDraft()
        draft.addAnchor(at: CGPoint(x: 10, y: 20))

        #expect(draft.anchors.count == 1)
        let anchor = draft.anchors[0]
        #expect(anchor.style == .corner)
        #expect(anchor.controlIn == anchor.point)
        #expect(anchor.controlOut == anchor.point)
    }

    @Test("Ziehen nach dem Klick erzeugt symmetrische Griffe")
    func draggingCreatesSymmetricHandles() {
        var draft = PenDraft()
        draft.addAnchor(at: CGPoint(x: 100, y: 100))
        draft.dragHandleOfLastAnchor(to: CGPoint(x: 130, y: 100))

        let anchor = draft.anchors[0]
        #expect(anchor.style == .symmetric)
        #expect(anchor.controlOut == CGPoint(x: 130, y: 100))
        // Der eingehende Griff spiegelt den ausgehenden am Anker.
        #expect(anchor.controlIn == CGPoint(x: 70, y: 100))
    }

    @Test("Weniger als zwei Anker ergeben keinen Pfad")
    func singleAnchorIsNoPath() {
        var draft = PenDraft()
        draft.addAnchor(at: .zero)
        #expect(draft.path(closed: false) == nil)
    }

    @Test("Zwei Anker ergeben einen offenen Pfad mit einem Segment")
    func twoAnchorsMakeOpenPath() throws {
        var draft = PenDraft()
        draft.addAnchor(at: CGPoint(x: 0, y: 0))
        draft.addAnchor(at: CGPoint(x: 50, y: 0))

        let path = try #require(draft.path(closed: false))
        #expect(path.subpaths.count == 1)
        #expect(path.subpaths[0].isClosed == false)
        #expect(path.subpaths[0].segments.count == 1)
    }

    @Test("Geschlossener Pfad bekommt das Rückschluss-Segment")
    func closedPathHasClosingSegment() throws {
        var draft = PenDraft()
        draft.addAnchor(at: CGPoint(x: 0, y: 0))
        draft.addAnchor(at: CGPoint(x: 50, y: 0))
        draft.addAnchor(at: CGPoint(x: 50, y: 50))

        let path = try #require(draft.path(closed: true))
        #expect(path.subpaths[0].isClosed)
        #expect(path.subpaths[0].segments.count == 3)
    }

    @Test("Der erste Anker wird zum Schliessen erkannt")
    func firstAnchorIsDetectedForClosing() {
        var draft = PenDraft()
        draft.addAnchor(at: CGPoint(x: 10, y: 10))
        draft.addAnchor(at: CGPoint(x: 90, y: 10))

        #expect(draft.isOverFirstAnchor(CGPoint(x: 12, y: 12), tolerance: 6))
        #expect(!draft.isOverFirstAnchor(CGPoint(x: 40, y: 40), tolerance: 6))
        // Mit nur einem Anker darf nicht geschlossen werden.
        var single = PenDraft()
        single.addAnchor(at: CGPoint(x: 10, y: 10))
        #expect(!single.isOverFirstAnchor(CGPoint(x: 10, y: 10), tolerance: 6))
    }

    @Test("Vorschau hängt ein Segment zum Mauszeiger an")
    func previewFollowsCursor() {
        var draft = PenDraft()
        draft.addAnchor(at: CGPoint(x: 0, y: 0))

        let withoutCursor = draft.previewPath(cursor: nil)
        #expect(withoutCursor.subpaths.first?.anchors.count == 1)

        let withCursor = draft.previewPath(cursor: CGPoint(x: 30, y: 40))
        #expect(withCursor.subpaths.first?.anchors.count == 2)
        #expect(withCursor.subpaths.first?.anchors.last?.point == CGPoint(x: 30, y: 40))
    }

    @Test("Letzten Anker zurücknehmen")
    func removeLastAnchor() {
        var draft = PenDraft()
        draft.addAnchor(at: CGPoint(x: 0, y: 0))
        draft.addAnchor(at: CGPoint(x: 10, y: 0))
        draft.removeLastAnchor()

        #expect(draft.anchors.count == 1)
        draft.removeLastAnchor()
        #expect(draft.isEmpty)
        // Auf einem leeren Entwurf darf das nicht abstürzen.
        draft.removeLastAnchor()
        #expect(draft.isEmpty)
    }
}

@Suite("VectorPath — Anker bearbeiten")
struct AnchorEditingTests {

    private func triangle() -> VectorPath {
        VectorPath(subpath: Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100)
        ]))
    }

    @Test("Treffertest findet den nächstgelegenen Anker")
    func hitTestFindsNearestAnchor() throws {
        let path = triangle()
        let hit = try #require(path.hitTestAnchor(at: CGPoint(x: 98, y: 3), tolerance: 8))

        #expect(hit.address.subpath == 0)
        #expect(hit.address.index == 1)
        #expect(hit.handle == .point)
    }

    @Test("Ausserhalb der Toleranz wird nichts getroffen")
    func hitTestMissesOutsideTolerance() {
        #expect(triangle().hitTestAnchor(at: CGPoint(x: 50, y: 50), tolerance: 8) == nil)
    }

    @Test("Griffe werden vor dem Anker selbst getroffen")
    func handlesTakePrecedenceOverPoint() throws {
        // Ein Anker, dessen ausgehender Griff dicht neben dem Anker liegt.
        let anchor = Anchor(
            point: CGPoint(x: 0, y: 0),
            controlIn: CGPoint(x: -10, y: 0),
            controlOut: CGPoint(x: 10, y: 0),
            style: .symmetric
        )
        let path = VectorPath(subpath: Subpath(
            anchors: [anchor, Anchor(corner: CGPoint(x: 100, y: 0))],
            isClosed: false
        ))

        let hit = try #require(path.hitTestAnchor(at: CGPoint(x: 11, y: 1), tolerance: 5))
        #expect(hit.handle == .controlOut)
    }

    @Test("Anker verschieben nimmt beide Griffe mit")
    func movingPointCarriesHandles() throws {
        let anchor = Anchor(
            point: CGPoint(x: 0, y: 0),
            controlIn: CGPoint(x: -10, y: 0),
            controlOut: CGPoint(x: 10, y: 0),
            style: .symmetric
        )
        let path = VectorPath(subpath: Subpath(
            anchors: [anchor, Anchor(corner: CGPoint(x: 100, y: 0))],
            isClosed: false
        ))

        let moved = path.movingHandle(
            .point,
            at: AnchorAddress(subpath: 0, index: 0),
            to: CGPoint(x: 5, y: 5)
        )
        let result = moved.subpaths[0].anchors[0]
        #expect(result.point == CGPoint(x: 5, y: 5))
        #expect(result.controlIn == CGPoint(x: -5, y: 5))
        #expect(result.controlOut == CGPoint(x: 15, y: 5))
    }

    @Test("Symmetrischer Anker spiegelt den Gegengriff exakt")
    func symmetricMirrorsOppositeHandle() {
        let anchor = Anchor(
            point: CGPoint(x: 0, y: 0),
            controlIn: CGPoint(x: -10, y: 0),
            controlOut: CGPoint(x: 10, y: 0),
            style: .symmetric
        )
        let path = VectorPath(subpath: Subpath(anchors: [anchor], isClosed: false))

        let moved = path.movingHandle(
            .controlOut,
            at: AnchorAddress(subpath: 0, index: 0),
            to: CGPoint(x: 0, y: 20)
        )
        let result = moved.subpaths[0].anchors[0]
        #expect(result.controlOut == CGPoint(x: 0, y: 20))
        #expect(result.controlIn == CGPoint(x: 0, y: -20))
    }

    @Test("Weicher Anker dreht den Gegengriff mit, behält aber dessen Länge")
    func smoothKeepsOppositeLength() {
        let anchor = Anchor(
            point: CGPoint(x: 0, y: 0),
            controlIn: CGPoint(x: -30, y: 0),   // Länge 30
            controlOut: CGPoint(x: 10, y: 0),
            style: .smooth
        )
        let path = VectorPath(subpath: Subpath(anchors: [anchor], isClosed: false))

        let moved = path.movingHandle(
            .controlOut,
            at: AnchorAddress(subpath: 0, index: 0),
            to: CGPoint(x: 0, y: 10)
        )
        let result = moved.subpaths[0].anchors[0]
        #expect(result.controlOut == CGPoint(x: 0, y: 10))
        // Gegenrichtung, aber weiterhin Länge 30.
        #expect(abs(result.controlIn.x - 0) < 0.0001)
        #expect(abs(result.controlIn.y - (-30)) < 0.0001)
    }

    @Test("Eckpunkt lässt den anderen Griff in Ruhe")
    func cornerLeavesOppositeAlone() {
        let anchor = Anchor(
            point: CGPoint(x: 0, y: 0),
            controlIn: CGPoint(x: -30, y: 0),
            controlOut: CGPoint(x: 10, y: 0),
            style: .corner
        )
        let path = VectorPath(subpath: Subpath(anchors: [anchor], isClosed: false))

        let moved = path.movingHandle(
            .controlOut,
            at: AnchorAddress(subpath: 0, index: 0),
            to: CGPoint(x: 0, y: 10)
        )
        #expect(moved.subpaths[0].anchors[0].controlIn == CGPoint(x: -30, y: 0))
    }

    @Test("Ungültige Adressen verändern nichts statt abzustürzen")
    func invalidAddressIsSafe() {
        let path = triangle()
        #expect(path.movingHandle(.point, at: AnchorAddress(subpath: 9, index: 0), to: .zero) == path)
        #expect(path.movingHandle(.point, at: AnchorAddress(subpath: 0, index: 99), to: .zero) == path)
    }
}
