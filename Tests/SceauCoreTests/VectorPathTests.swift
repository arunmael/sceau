import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("VectorPath — Grundlagen")
struct VectorPathTests {

    @Test("Eckpunkte erzeugen gerade Segmente")
    func cornerAnchorsProduceLines() {
        let subpath = Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10)
        ])
        let segments = subpath.segments

        #expect(segments.count == 3, "geschlossen: drei Ecken ergeben drei Segmente")
        let allStraight = segments.allSatisfy { $0.isLine }
        #expect(allStraight)
        #expect(segments[2].start == CGPoint(x: 10, y: 10))
        #expect(segments[2].end == CGPoint(x: 0, y: 0), "letztes Segment schliesst zum Anfang")
    }

    @Test("Offener Teilpfad hat ein Segment weniger")
    func openSubpathHasOneSegmentLess() {
        let subpath = Subpath(
            anchors: [
                Anchor(corner: CGPoint(x: 0, y: 0)),
                Anchor(corner: CGPoint(x: 10, y: 0)),
                Anchor(corner: CGPoint(x: 10, y: 10))
            ],
            isClosed: false
        )
        #expect(subpath.segments.count == 2)
    }

    @Test("Hüllrahmen berücksichtigt die Kurvenausbuchtung, nicht die Kontrollpunkte")
    func boundsFollowCurveNotControlPoints() {
        // Eine Kurve von (0,0) nach (100,0), deren Kontrollpunkte weit auf y=100
        // liegen. Die Kurve selbst erreicht nur y = 75 (3/4 der Kontrollhöhe),
        // der Hüllrahmen darf also nicht bis 100 gehen.
        let anchors = [
            Anchor(
                point: CGPoint(x: 0, y: 0),
                controlIn: CGPoint(x: 0, y: 0),
                controlOut: CGPoint(x: 0, y: 100)
            ),
            Anchor(
                point: CGPoint(x: 100, y: 0),
                controlIn: CGPoint(x: 100, y: 100),
                controlOut: CGPoint(x: 100, y: 0)
            )
        ]
        let path = VectorPath(subpath: Subpath(anchors: anchors, isClosed: false))

        #expect(abs(path.bounds.maxY - 75) < 0.01, "tatsächlich erreicht: \(path.bounds.maxY)")
        #expect(abs(path.bounds.minX) < 0.01)
        #expect(abs(path.bounds.maxX - 100) < 0.01)
    }

    @Test("Verschieben bewegt Anker und beide Griffe gleich weit")
    func moveTranslatesAnchorAndHandles() {
        let anchor = Anchor(
            point: CGPoint(x: 1, y: 2),
            controlIn: CGPoint(x: 0, y: 0),
            controlOut: CGPoint(x: 3, y: 4)
        )
        let path = VectorPath(subpath: Subpath(anchors: [anchor], isClosed: false))
            .moved(by: CGVector(dx: 10, dy: 20))
        let moved = path.subpaths[0].anchors[0]

        #expect(moved.point == CGPoint(x: 11, y: 22))
        #expect(moved.controlIn == CGPoint(x: 10, y: 20))
        #expect(moved.controlOut == CGPoint(x: 13, y: 24))
    }

    @Test("Dokumentmodell überlebt eine JSON-Rundreise verlustfrei")
    func documentSurvivesJSONRoundTrip() throws {
        var document = Document.empty()
        document.nodes = [
            Node(shape: .rectangle(frame: CGRect(x: 10, y: 20, width: 30, height: 40), cornerRadius: 5)),
            Node(shape: .star(frame: CGRect(x: 0, y: 0, width: 100, height: 100), points: 5, innerRatio: 0.4)),
            Node(
                name: "Gruppe",
                content: .group(children: [
                    Node(shape: .ellipse(frame: CGRect(x: 1, y: 2, width: 3, height: 4)))
                ])
            )
        ]

        let data = try JSONEncoder().encode(document)
        let restored = try JSONDecoder().decode(Document.self, from: data)

        #expect(restored == document)
    }
}
