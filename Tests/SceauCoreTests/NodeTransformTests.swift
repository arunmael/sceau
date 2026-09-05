import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("NodeTransform — Bewegen und Skalieren")
struct NodeTransformTests {

    private func rectangleNode(
        _ frame: CGRect,
        cornerRadius: CGFloat = 0
    ) -> Node {
        Node(shape: .rectangle(frame: frame, cornerRadius: cornerRadius))
    }

    @Test("Bewegen verschiebt den Rahmen und lässt die Form parametrisch")
    func moveKeepsShapeParametric() {
        let node = rectangleNode(CGRect(x: 10, y: 20, width: 30, height: 40), cornerRadius: 5)
        let moved = NodeTransform.moved(node, by: CGVector(dx: 5, dy: -10))

        guard case let .shape(.rectangle(frame, radius)) = moved.content else {
            Issue.record("Bewegen darf die Grundform nicht in einen Pfad verwandeln")
            return
        }
        #expect(frame == CGRect(x: 15, y: 10, width: 30, height: 40))
        #expect(radius == 5, "Eckradius darf sich beim blossen Bewegen nicht ändern")
    }

    @Test("Bewegen um null verändert den Knoten exakt nicht")
    func zeroMoveIsIdentity() {
        let node = rectangleNode(CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(NodeTransform.moved(node, by: CGVector(dx: 0, dy: 0)) == node)
    }

    @Test("Bewegen einer Gruppe bewegt alle Kinder")
    func moveGroupMovesChildren() {
        let group = Node(
            name: "Gruppe",
            content: .group(children: [
                rectangleNode(CGRect(x: 0, y: 0, width: 10, height: 10)),
                rectangleNode(CGRect(x: 20, y: 20, width: 10, height: 10))
            ])
        )
        let moved = NodeTransform.moved(group, by: CGVector(dx: 100, dy: 0))

        let frames = (moved.children ?? []).compactMap { child -> CGRect? in
            guard case let .shape(spec) = child.content else { return nil }
            return spec.frame
        }
        #expect(frames == [
            CGRect(x: 100, y: 0, width: 10, height: 10),
            CGRect(x: 120, y: 20, width: 10, height: 10)
        ])
    }

    @Test("Skalieren bildet den Rahmen auf den Zielrahmen ab")
    func resizeMapsFrame() {
        let source = CGRect(x: 0, y: 0, width: 100, height: 100)
        let target = CGRect(x: 0, y: 0, width: 200, height: 50)
        let node = rectangleNode(CGRect(x: 10, y: 10, width: 20, height: 20))

        let resized = NodeTransform.resized(node, from: source, to: target)
        guard case let .shape(.rectangle(frame, _)) = resized.content else {
            Issue.record("Erwartet wurde weiterhin ein Rechteck")
            return
        }
        // Doppelte Breite, halbe Höhe.
        #expect(frame == CGRect(x: 20, y: 5, width: 40, height: 10))
    }

    @Test("Eckradius skaliert mit, aber nur mit dem kleineren Faktor")
    func cornerRadiusScalesWithSmallerFactor() {
        let source = CGRect(x: 0, y: 0, width: 100, height: 100)
        let target = CGRect(x: 0, y: 0, width: 400, height: 200) // 4× und 2×
        let node = rectangleNode(CGRect(x: 0, y: 0, width: 100, height: 100), cornerRadius: 10)

        let resized = NodeTransform.resized(node, from: source, to: target)
        guard case let .shape(.rectangle(_, radius)) = resized.content else {
            Issue.record("Erwartet wurde weiterhin ein Rechteck")
            return
        }
        #expect(radius == 20, "kleinerer Faktor ist 2, also 10 → 20; sonst würde die Ecke verzerren")
    }

    @Test("Entarteter Ausgangsrahmen lässt den Knoten unverändert statt NaN zu erzeugen")
    func degenerateSourceIsSafe() {
        let node = rectangleNode(CGRect(x: 5, y: 5, width: 10, height: 10))
        let resized = NodeTransform.resized(
            node,
            from: CGRect(x: 0, y: 0, width: 0, height: 100),
            to: CGRect(x: 0, y: 0, width: 50, height: 50)
        )
        #expect(resized == node)
    }

    @Test("Skalieren eines Pfades bewegt dessen Anker mit")
    func resizePathMovesAnchors() {
        let path = VectorPath(subpath: Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10)
        ]))
        let node = Node(name: "Pfad", content: .path(path))

        let resized = NodeTransform.resized(
            node,
            from: CGRect(x: 0, y: 0, width: 10, height: 10),
            to: CGRect(x: 0, y: 0, width: 20, height: 20)
        )
        guard case let .path(scaled) = resized.content else {
            Issue.record("Erwartet wurde weiterhin ein Pfad")
            return
        }
        #expect(scaled.bounds.width == 20)
        #expect(scaled.subpaths[0].anchors[1].point == CGPoint(x: 20, y: 0))
    }

    @Test("Schriftgrösse folgt der Höhe")
    func textScalesWithHeight() {
        let node = Node(name: "Text", content: .text(TextSpec(string: "A", fontSize: 40)))
        let resized = NodeTransform.resized(
            node,
            from: CGRect(x: 0, y: 0, width: 100, height: 100),
            to: CGRect(x: 0, y: 0, width: 100, height: 50)
        )
        guard case let .text(spec) = resized.content else {
            Issue.record("Erwartet wurde weiterhin Text")
            return
        }
        #expect(spec.fontSize == 20)
    }

    // MARK: - Verzerren

    @Test("Verzerren einer Einzelform löst sie in einen Pfad auf und setzt die Rotation zurück")
    func distortingShapeResolvesToPathAndResetsRotation() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let node = Node(name: "Rechteck", rotation: 0.3, content: .shape(.rectangle(frame: frame, cornerRadius: 0)))
        let corners = QuadCorners(
            topLeft: CGPoint(x: -10, y: 0), topRight: CGPoint(x: 110, y: 0),
            bottomRight: CGPoint(x: 100, y: 60), bottomLeft: CGPoint(x: 0, y: 60)
        )
        // Frame muss die tatsächlich gerenderte (rotierte) Kontur sein, sonst
        // passt die Quelle nicht zu dem, was der Nutzer beim Ziehen sieht.
        let source = NodeGeometry.bounds(for: node)

        let distorted = NodeTransform.distorted(node, from: source, to: corners)

        guard case .path = distorted.content else {
            Issue.record("Verzerren muss die Form in einen Pfad auflösen — nicht affin, nicht mehr parametrisch")
            return
        }
        #expect(distorted.rotation == 0)
    }

    @Test("Verzerren einer unrotierten Gruppe behält die Gruppenstruktur und die Einzelstile der Kinder")
    func distortingUnrotatedGroupPreservesChildrenAndTheirStyles() {
        let redStyle = Style(fill: .solid(RGBAColor(red: 1, green: 0, blue: 0)))
        let blueStyle = Style(fill: .solid(RGBAColor(red: 0, green: 0, blue: 1)))
        let red = Node(name: "Rot", style: redStyle, content: .shape(.rectangle(frame: CGRect(x: 0, y: 0, width: 50, height: 50), cornerRadius: 0)))
        let blue = Node(name: "Blau", style: blueStyle, content: .shape(.rectangle(frame: CGRect(x: 50, y: 0, width: 50, height: 50), cornerRadius: 0)))
        let group = Node(name: "Gruppe", rotation: 0, content: .group(children: [red, blue]))

        let source = CGRect(x: 0, y: 0, width: 100, height: 50)
        let corners = QuadCorners(
            topLeft: .zero, topRight: CGPoint(x: 120, y: 0),
            bottomRight: CGPoint(x: 100, y: 60), bottomLeft: CGPoint(x: 0, y: 60)
        )

        let distorted = NodeTransform.distorted(group, from: source, to: corners)

        guard case let .group(children) = distorted.content else {
            Issue.record("Eine unrotierte Gruppe muss nach dem Verzerren weiterhin eine Gruppe sein")
            return
        }
        #expect(children.count == 2)
        #expect(children[0].style == redStyle, "Der eigene Stil des ersten Kindes darf nicht verloren gehen")
        #expect(children[1].style == blueStyle, "Der eigene Stil des zweiten Kindes darf nicht verloren gehen")
        for child in children {
            guard case .path = child.content else {
                Issue.record("Jedes Kind muss einzeln in einen Pfad aufgelöst sein")
                return
            }
        }
    }

    @Test("Verzerren einer rotierten Gruppe schreibt sie als einen Pfad mit dem Gruppenstil fest")
    func distortingRotatedGroupFallsBackToFlattenedPath() {
        let red = Node(name: "Rot", style: Style(fill: .solid(.black)), content: .shape(.rectangle(frame: CGRect(x: 0, y: 0, width: 50, height: 50), cornerRadius: 0)))
        let groupStyle = Style(fill: .solid(RGBAColor(red: 0, green: 1, blue: 0)))
        let group = Node(name: "Gruppe", rotation: 0.2, style: groupStyle, content: .group(children: [red]))
        let source = NodeGeometry.bounds(for: group)
        let corners = QuadCorners(rect: source)

        let distorted = NodeTransform.distorted(group, from: source, to: corners)

        guard case .path = distorted.content else {
            Issue.record("Eine rotierte Gruppe lässt sich nicht ohne Weiteres pro Kind verzerren — bekannte Einschränkung, siehe Kommentar in NodeTransform")
            return
        }
        #expect(distorted.style == groupStyle)
        #expect(distorted.rotation == 0)
    }
}
