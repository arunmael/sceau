import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

/// Belastungsproben mit vielteiligen und entarteten Dokumenten.
///
/// Der Entwicklungsplan stellt Stabilität über jedes Einzelfeature: Eine App,
/// die bei einem komplexen Logo abstürzt oder einfriert, ist wertlos. Diese
/// Suite prüft deshalb nicht Schönheit, sondern dass die heiklen Stellen
/// überhaupt durchlaufen — boolesche Verknüpfungen, Export und die
/// rekursiven Baumoperationen.
@Suite("Belastungsproben — vielteilige und entartete Dokumente")
struct StressTests {

    private func star(points: Int, at origin: CGPoint, size: CGFloat) -> VectorPath {
        ShapeGeometry.path(for: .star(
            frame: CGRect(x: origin.x, y: origin.y, width: size, height: size),
            points: points,
            innerRatio: 0.45
        ))
    }

    @Test("Zwei vielzackige Sterne lassen sich verknüpfen")
    func booleanOnManyPointedStars() throws {
        let a = star(points: 60, at: .zero, size: 500)
        let b = star(points: 60, at: CGPoint(x: 120, y: 120), size: 500)

        let start = Date()
        let result = try BooleanOperator.apply(.subtract, subject: a, clip: b)
        let seconds = Date().timeIntervalSince(start)

        #expect(!result.isEmpty)
        // Kein hartes Zeitlimit — das wäre auf fremder Hardware unzuverlässig.
        // Der Wert steht im Protokoll, damit eine Verschlechterung auffällt.
        print("  Verknüpfung zweier 60-zackiger Sterne: \(String(format: "%.3f", seconds)) s, "
            + "\(result.subpaths.count) Teilpfade, \(result.allAnchors.count) Anker")
    }

    @Test("Eine Kette boolescher Verknüpfungen bleibt stabil")
    func chainOfBooleanOperations() throws {
        var accumulated = star(points: 12, at: .zero, size: 400)

        // Wiederholtes Verknüpfen ist der Fall, der in der Praxis entgleist:
        // Jedes Ergebnis ist Eingabe des nächsten Schritts, Fehler summieren sich.
        for step in 1...12 {
            let offset = CGFloat(step) * 15
            let next = star(points: 8, at: CGPoint(x: offset, y: offset), size: 300)
            accumulated = try BooleanOperator.apply(.union, subject: accumulated, clip: next)
        }

        #expect(!accumulated.isEmpty)
        let allFinite = accumulated.allAnchors.allSatisfy {
            $0.point.x.isFinite && $0.point.y.isFinite
        }
        #expect(allFinite, "keine entgleisten Koordinaten nach zwölf Verknüpfungen")
    }

    @Test("Ein Dokument mit 300 Formen exportiert vollständig")
    func largeDocumentExports() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 1024, height: 1024)))
        for index in 0..<300 {
            let x = CGFloat(index % 20) * 50
            let y = CGFloat(index / 20) * 50
            document.nodes.append(Node(shape: .star(
                frame: CGRect(x: x, y: y, width: 40, height: 40),
                points: 6,
                innerRatio: 0.5
            )))
        }

        let svg = SVGExporter.export(document)
        _ = try XMLDocument(xmlString: svg, options: [.nodePreserveWhitespace])
        #expect(svg.components(separatedBy: "<path").count - 1 == 300)

        let png = try RasterExporter.pngData(document, pixelWidth: 512, pixelHeight: 512)
        #expect(!png.isEmpty)

        let pdf = try PDFExporter.pdfData(document)
        #expect(!pdf.isEmpty)
    }

    @Test("Tief verschachtelte Gruppen laufen nicht in die Rekursion")
    func deeplyNestedGroups() {
        // Hundert Ebenen tief — weit jenseits dessen, was von Hand entsteht,
        // aber durch wiederholtes Gruppieren erreichbar.
        var node = Node(shape: .ellipse(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        for _ in 0..<100 {
            node = Node(name: "Gruppe", content: .group(children: [node]))
        }

        var document = Document.empty()
        document.nodes = [node]

        #expect(node.flattenedIDs.count == 101)
        #expect(!NodeGeometry.bounds(for: node).isNull)
        #expect(document.flattenedNodes.count == 101)

        let moved = NodeTransform.moved(node, by: CGVector(dx: 5, dy: 5))
        #expect(NodeGeometry.bounds(for: moved).minX == 5)
    }

    @Test("Ein selbstüberschneidender Pfad mit vielen Segmenten stürzt nicht ab")
    func selfIntersectingMonsterPath() {
        // Sternpolygon mit grosser Schrittweite: läuft mehrfach um sich selbst
        // und überschneidet sich dabei permanent.
        var points: [CGPoint] = []
        let count = 401
        for index in 0..<count {
            let angle = CGFloat(index) * 2 * .pi * 173 / CGFloat(count)
            points.append(CGPoint(x: 250 + cos(angle) * 240, y: 250 + sin(angle) * 240))
        }
        let monster = VectorPath(subpath: Subpath(closedPolygon: points))
        let square = VectorPath(subpath: Subpath(closedPolygon: [
            CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 100),
            CGPoint(x: 400, y: 400), CGPoint(x: 100, y: 400)
        ]))

        // Erwartet wird ein beherrschtes Ergebnis: entweder eine Fläche oder
        // ein Fehler. Ein Absturz wäre der Fehlschlag.
        do {
            let result = try BooleanOperator.apply(.intersect, subject: monster, clip: square)
            #expect(!result.isEmpty)
        } catch let error as BooleanError {
            #expect(error == .emptyResult || error == .emptyInput)
        } catch {
            Issue.record("unerwarteter Fehler: \(error)")
        }
    }

    @Test("Entartete Zahlen erzeugen keine kaputte Geometrie")
    func degenerateNumbersAreContained() {
        let cases: [CGRect] = [
            CGRect(x: 0, y: 0, width: 0, height: 100),
            CGRect(x: 0, y: 0, width: -50, height: -50),
            CGRect(x: CGFloat.nan, y: CGFloat.nan, width: 10, height: 10),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10),
            CGRect(x: 1e12, y: 1e12, width: 1, height: 1)
        ]

        for frame in cases {
            let path = ShapeGeometry.path(for: .rectangle(frame: frame, cornerRadius: 5))
            let hasBadNumbers = path.allAnchors.contains {
                !$0.point.x.isFinite || !$0.point.y.isFinite
            }
            #expect(!hasBadNumbers, "entartete Werte dürfen nicht in die Geometrie gelangen: \(frame)")
        }
    }

    @Test("Ein Pfad mit sehr vielen Ankern lässt sich abflachen und exportieren")
    func veryDetailedPathSurvivesExport() throws {
        var anchors: [Anchor] = []
        for index in 0..<2000 {
            let angle = CGFloat(index) / 2000 * 2 * .pi
            let radius: CGFloat = 200 + sin(angle * 30) * 20
            anchors.append(Anchor(corner: CGPoint(
                x: 250 + cos(angle) * radius,
                y: 250 + sin(angle) * radius
            )))
        }
        let path = VectorPath(subpath: Subpath(anchors: anchors, isClosed: true))

        var document = Document(artboard: Artboard(size: CGSize(width: 500, height: 500)))
        document.nodes = [Node(name: "Feindetail", content: .path(path))]

        let svg = SVGExporter.export(document)
        _ = try XMLDocument(xmlString: svg, options: [.nodePreserveWhitespace])

        let polygons = Flattener.polygons(of: path, tolerance: Flattener.defaultTolerance)
        #expect(polygons.first?.count == 2000, "gerade Segmente dürfen keine Zwischenpunkte erzeugen")
    }
}
