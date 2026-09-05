import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("ShapeGeometry — Grundformen zu Pfaden")
struct ShapeGeometryTests {

    // MARK: - Rechteck

    @Test("Rechteck ohne Eckradius: vier Eckanker im Uhrzeigersinn ab links-oben")
    func rectangleWithoutRadiusHasFourCornerAnchors() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 50)
        let path = ShapeGeometry.path(for: .rectangle(frame: frame, cornerRadius: 0))

        #expect(path.subpaths.count == 1)
        let subpath = path.subpaths[0]
        #expect(subpath.isClosed)
        #expect(subpath.anchors.count == 4)
        #expect(subpath.anchors[0].point == CGPoint(x: 10, y: 20))
        #expect(subpath.anchors[1].point == CGPoint(x: 110, y: 20))
        #expect(subpath.anchors[2].point == CGPoint(x: 110, y: 70))
        #expect(subpath.anchors[3].point == CGPoint(x: 10, y: 70))
        let allCorners = subpath.anchors.allSatisfy { $0.style == .corner }
        #expect(allCorners)
    }

    @Test("Rechteck-Hüllrahmen entspricht dem Frame")
    func rectangleBoundsMatchFrame() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 50)
        let path = ShapeGeometry.path(for: .rectangle(frame: frame, cornerRadius: 0))
        let bounds = path.bounds

        #expect(abs(bounds.minX - frame.minX) < 0.01)
        #expect(abs(bounds.minY - frame.minY) < 0.01)
        #expect(abs(bounds.maxX - frame.maxX) < 0.01)
        #expect(abs(bounds.maxY - frame.maxY) < 0.01)
    }

    @Test("Abgerundetes Rechteck: Anker sind smooth und Hüllrahmen bleibt der Frame")
    func roundedRectangleAnchorsAreSmoothAndBoundsMatchFrame() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let path = ShapeGeometry.path(for: .rectangle(frame: frame, cornerRadius: 10))
        let subpath = path.subpaths[0]

        let allSmooth = subpath.anchors.allSatisfy { $0.style == .smooth }
        #expect(allSmooth)

        let bounds = path.bounds
        #expect(abs(bounds.minX - frame.minX) < 0.01)
        #expect(abs(bounds.minY - frame.minY) < 0.01)
        #expect(abs(bounds.maxX - frame.maxX) < 0.01)
        #expect(abs(bounds.maxY - frame.maxY) < 0.01)
    }

    @Test("Eckradius wird auf die halbe kürzere Seite begrenzt")
    func cornerRadiusIsClampedToHalfShorterSide() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let path = ShapeGeometry.path(for: .rectangle(frame: frame, cornerRadius: 999))
        let bounds = path.bounds

        // effektiver Radius: 25 (= min(100,50)/2) — Hüllrahmen bleibt trotzdem der Frame
        #expect(abs(bounds.minX - frame.minX) < 0.01)
        #expect(abs(bounds.minY - frame.minY) < 0.01)
        #expect(abs(bounds.maxX - frame.maxX) < 0.01)
        #expect(abs(bounds.maxY - frame.maxY) < 0.01)
    }

    // MARK: - Ellipse

    @Test("Ellipse hat vier symmetrische Anker")
    func ellipseHasFourSymmetricAnchors() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 60)
        let path = ShapeGeometry.path(for: .ellipse(frame: frame))
        let subpath = path.subpaths[0]

        #expect(subpath.anchors.count == 4)
        let allSymmetric = subpath.anchors.allSatisfy { $0.style == .symmetric }
        #expect(allSymmetric)
    }

    @Test("Ellipsen-Hüllrahmen entspricht dem Frame")
    func ellipseBoundsMatchFrame() {
        let frame = CGRect(x: 5, y: 5, width: 100, height: 60)
        let path = ShapeGeometry.path(for: .ellipse(frame: frame))
        let bounds = path.bounds

        #expect(abs(bounds.minX - frame.minX) < 0.01)
        #expect(abs(bounds.minY - frame.minY) < 0.01)
        #expect(abs(bounds.maxX - frame.maxX) < 0.01)
        #expect(abs(bounds.maxY - frame.maxY) < 0.01)
    }

    @Test("Ellipsenfläche liegt nahe an π·a·b (Kappa-Näherung)")
    func ellipseAreaApproximatesPiAB() {
        let a: CGFloat = 50
        let b: CGFloat = 30
        let frame = CGRect(x: 0, y: 0, width: a * 2, height: b * 2)
        let path = ShapeGeometry.path(for: .ellipse(frame: frame))
        let subpath = path.subpaths[0]

        // Feine Unterteilung der Kurven, dann Shoelace-Formel für die Fläche.
        var points: [CGPoint] = []
        let steps = 200
        for segment in subpath.segments {
            for i in 0..<steps {
                let t = CGFloat(i) / CGFloat(steps)
                points.append(segment.point(at: t))
            }
        }

        var area: CGFloat = 0
        for i in 0..<points.count {
            let p0 = points[i]
            let p1 = points[(i + 1) % points.count]
            area += p0.x * p1.y - p1.x * p0.y
        }
        area = abs(area) / 2

        let expected = CGFloat.pi * a * b
        let relativeError = abs(area - expected) / expected
        #expect(relativeError < 0.001, "Fläche \(area), erwartet \(expected), relativer Fehler \(relativeError)")
    }

    // MARK: - Polygon

    @Test("Polygon mit 6 Ecken hat 6 Eckanker, erste Ecke oben und mittig")
    func hexagonHasSixCornerAnchorsFirstAtTop() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = ShapeGeometry.path(for: .polygon(frame: frame, sides: 6))
        let subpath = path.subpaths[0]

        #expect(subpath.anchors.count == 6)
        let allCorners = subpath.anchors.allSatisfy { $0.style == .corner }
        #expect(allCorners)

        let first = subpath.anchors[0].point
        #expect(abs(first.x - 50) < 0.01, "erste Ecke horizontal mittig")
        #expect(abs(first.y - 0) < 0.01, "erste Ecke oben (kleinstes y)")
    }

    @Test("Polygon: sides wird auf mindestens 3 begrenzt")
    func polygonSidesClampedToAtLeastThree() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = ShapeGeometry.path(for: .polygon(frame: frame, sides: 1))
        #expect(path.subpaths[0].anchors.count == 3)
    }

    // MARK: - Stern

    @Test("Stern mit 5 Zacken hat 10 Anker, die im Abstand zum Mittelpunkt alternieren")
    func fivePointStarHasTenAlternatingAnchors() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let path = ShapeGeometry.path(for: .star(frame: frame, points: 5, innerRatio: 0.5))
        let subpath = path.subpaths[0]

        #expect(subpath.anchors.count == 10)
        let allCorners = subpath.anchors.allSatisfy { $0.style == .corner }
        #expect(allCorners)

        func distance(_ p: CGPoint) -> CGFloat {
            hypot(p.x - center.x, p.y - center.y)
        }

        let outerDistances = stride(from: 0, to: 10, by: 2).map { distance(subpath.anchors[$0].point) }
        let innerDistances = stride(from: 1, to: 10, by: 2).map { distance(subpath.anchors[$0].point) }

        // Alle äusseren Ecken gleich weit entfernt, alle inneren gleich weit —
        // und die äusseren deutlich weiter als die inneren.
        for d in outerDistances {
            #expect(abs(d - outerDistances[0]) < 0.5)
        }
        for d in innerDistances {
            #expect(abs(d - innerDistances[0]) < 0.5)
        }
        #expect(outerDistances[0] > innerDistances[0])

        // erste äussere Ecke oben
        let first = subpath.anchors[0].point
        #expect(abs(first.x - center.x) < 0.01)
        #expect(first.y < center.y)
    }

    @Test("Stern: points und innerRatio werden begrenzt")
    func starParametersAreClamped() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = ShapeGeometry.path(for: .star(frame: frame, points: 1, innerRatio: 5))
        // points auf mind. 3 begrenzt -> 6 Anker
        #expect(path.subpaths[0].anchors.count == 6)
    }

    // MARK: - Squircle (App-Icon-Form)

    @Test("Squircle: geschlossener Pfad, dessen Hüllrahmen exakt dem Frame entspricht")
    func squircleBoundsMatchFrame() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 60)
        let path = ShapeGeometry.path(for: .squircle(frame: frame))
        let subpath = path.subpaths[0]

        #expect(subpath.isClosed)
        let bounds = path.bounds
        #expect(abs(bounds.minX - frame.minX) < 0.5)
        #expect(abs(bounds.minY - frame.minY) < 0.5)
        #expect(abs(bounds.maxX - frame.maxX) < 0.5)
        #expect(abs(bounds.maxY - frame.maxY) < 0.5)
    }

    @Test("Squircle: viele Anker für eine glatte Kurve, keiner ausserhalb des Frames")
    func squircleHasManyAnchorsInsideFrame() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = ShapeGeometry.path(for: .squircle(frame: frame))
        let subpath = path.subpaths[0]

        #expect(subpath.anchors.count >= 32)
        for anchor in subpath.anchors {
            #expect(anchor.point.x >= frame.minX - 0.5 && anchor.point.x <= frame.maxX + 0.5)
            #expect(anchor.point.y >= frame.minY - 0.5 && anchor.point.y <= frame.maxY + 0.5)
        }
    }

    @Test("Squircle: bei quadratischem Frame liegt die Kontur strikt innerhalb des einbeschriebenen Kreises der Ecken, aber ausserhalb der Ellipse — typische Squircle-Silhouette")
    func squircleShapeIsBetweenEllipseAndRectangle() {
        // Superellipse mit Exponent > 2 wölbt sich näher an die Ecken heran als
        // eine Ellipse, bleibt aber innerhalb des Rechtecks — das ist genau die
        // "App-Icon"-Silhouette, die eine reine Ellipse nicht liefert.
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        func polygonArea(_ path: VectorPath) -> CGFloat {
            let subpath = path.subpaths[0]
            var points: [CGPoint] = []
            let steps = 100
            for segment in subpath.segments {
                for i in 0..<steps {
                    points.append(segment.point(at: CGFloat(i) / CGFloat(steps)))
                }
            }
            var area: CGFloat = 0
            for i in 0..<points.count {
                let p0 = points[i]
                let p1 = points[(i + 1) % points.count]
                area += p0.x * p1.y - p1.x * p0.y
            }
            return abs(area) / 2
        }

        let ellipseArea = polygonArea(ShapeGeometry.path(for: .ellipse(frame: frame)))
        let squircleArea = polygonArea(ShapeGeometry.path(for: .squircle(frame: frame)))
        let rectArea = frame.width * frame.height

        #expect(squircleArea > ellipseArea)
        #expect(squircleArea < rectArea)
    }

    // MARK: - Entartete Rahmen

    @Test("Entartete Rahmen (Breite/Höhe <= 0) erzeugen einen leeren Pfad statt abzustürzen")
    func degenerateFramesProduceEmptyPath() {
        let zeroWidth = CGRect(x: 0, y: 0, width: 0, height: 50)
        let zeroHeight = CGRect(x: 0, y: 0, width: 50, height: 0)
        let negative = CGRect(x: 0, y: 0, width: -10, height: -10)

        for frame in [zeroWidth, zeroHeight, negative] {
            #expect(ShapeGeometry.path(for: .rectangle(frame: frame, cornerRadius: 5)).isEmpty)
            #expect(ShapeGeometry.path(for: .ellipse(frame: frame)).isEmpty)
            #expect(ShapeGeometry.path(for: .polygon(frame: frame, sides: 5)).isEmpty)
            #expect(ShapeGeometry.path(for: .star(frame: frame, points: 5, innerRatio: 0.5)).isEmpty)
            #expect(ShapeGeometry.path(for: .squircle(frame: frame)).isEmpty)
        }
    }
}

@Suite("NodeGeometry — aufgelöste Kontur und Hüllrahmen von Knoten")
struct NodeGeometryTests {

    @Test("Shape-Knoten liefert dieselbe Geometrie wie ShapeGeometry.path")
    func shapeNodeMatchesShapeGeometry() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let spec = ShapeSpec.rectangle(frame: frame, cornerRadius: 0)
        let node = Node(shape: spec)

        #expect(NodeGeometry.path(for: node) == ShapeGeometry.path(for: spec))
    }

    @Test("Path-Knoten liefert den Pfad unverändert")
    func pathNodeReturnsPathDirectly() {
        let subpath = Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)
        ])
        let vectorPath = VectorPath(subpath: subpath)
        let node = Node(name: "Pfad", content: .path(vectorPath))

        #expect(NodeGeometry.path(for: node) == vectorPath)
    }

    @Test("Text-Knoten wird über die Glyphenkonturen aufgelöst")
    func textNodeResolvesToGlyphOutlines() {
        let spec = TextSpec(string: "Hallo", fontName: "Helvetica", fontSize: 24, origin: CGPoint(x: 0, y: 100))
        let node = Node(name: "Text", content: .text(spec))
        let path = NodeGeometry.path(for: node)

        #expect(!path.isEmpty, "Textknoten müssen dieselbe Kontur liefern, die auch exportiert wird")
        // Oberlängen liegen über der Grundlinie, also bei kleinerem y.
        #expect(path.bounds.minY < 100)
        #expect(path.bounds.maxY <= 100.5)
    }

    @Test("Leerer Text ergibt weiterhin keine Kontur")
    func emptyTextNodeHasNoOutline() {
        let node = Node(name: "Text", content: .text(TextSpec(string: "", fontSize: 24)))
        #expect(NodeGeometry.path(for: node).isEmpty)
    }

    @Test("Gruppen-Hüllrahmen ist die Vereinigung der Kinder-Hüllrahmen")
    func groupBoundsIsUnionOfChildren() {
        let frameA = CGRect(x: 0, y: 0, width: 10, height: 10)
        let frameB = CGRect(x: 50, y: 50, width: 20, height: 20)
        let childA = Node(shape: .rectangle(frame: frameA, cornerRadius: 0))
        let childB = Node(shape: .rectangle(frame: frameB, cornerRadius: 0))
        let group = Node(name: "Gruppe", content: .group(children: [childA, childB]))

        let bounds = NodeGeometry.bounds(for: group)
        let expected = frameA.union(frameB)

        #expect(abs(bounds.minX - expected.minX) < 0.01)
        #expect(abs(bounds.minY - expected.minY) < 0.01)
        #expect(abs(bounds.maxX - expected.maxX) < 0.01)
        #expect(abs(bounds.maxY - expected.maxY) < 0.01)
    }

    @Test("Rotation 0 verändert die Geometrie exakt nicht")
    func zeroRotationDoesNotChangeGeometry() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let spec = ShapeSpec.rectangle(frame: frame, cornerRadius: 0)
        let node = Node(name: "Rechteck", rotation: 0, content: .shape(spec))

        #expect(NodeGeometry.path(for: node) == ShapeGeometry.path(for: spec))
    }

    @Test("Rotation um 90° eines 100x50-Rechtecks ergibt 50x100-Hüllrahmen mit gleichem Mittelpunkt")
    func ninetyDegreeRotationSwapsBoundsDimensions() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 50)
        let spec = ShapeSpec.rectangle(frame: frame, cornerRadius: 0)
        let node = Node(name: "Rechteck", rotation: .pi / 2, content: .shape(spec))

        let bounds = NodeGeometry.bounds(for: node)

        #expect(abs(bounds.width - 50) < 0.5)
        #expect(abs(bounds.height - 100) < 0.5)
        #expect(abs(bounds.midX - frame.midX) < 0.5)
        #expect(abs(bounds.midY - frame.midY) < 0.5)
    }

    @Test("Leerer Pfad hat Hüllrahmen .null")
    func emptyPathHasNullBounds() {
        let node = Node(name: "Text", content: .text(TextSpec(string: "", fontSize: 12)))
        #expect(NodeGeometry.bounds(for: node) == .null)
    }
}
