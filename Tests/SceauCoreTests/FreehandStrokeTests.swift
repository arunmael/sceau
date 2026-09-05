import CoreGraphics
import Testing

@testable import SceauCore

/// Aus missing.md: "Freihand zeichnen Tool mit mehreren Stiften". Die
/// eigentliche Kurvenglättung (Douglas-Peucker + Catmull-Rom) ist Kernlogik
/// der Vektor-Pfad-Berechnung — hier test-first abgesichert, bevor die
/// Werkzeug-Anbindung in der App entsteht.
@Suite("FreehandStroke — grobe Punktfolge zu geglättetem Pfad")
struct FreehandStrokeTests {

    @Test("Weniger als zwei Punkte ergeben einen leeren Pfad")
    func tooFewPointsIsEmpty() {
        #expect(FreehandStroke.path(from: [], smoothingTolerance: 1).isEmpty)
    }

    @Test("Ein einzelner Punkt (Tupfer) ergibt einen sichtbaren, aber sehr kurzen Pfad")
    func singlePointProducesDot() {
        let path = FreehandStroke.path(from: [CGPoint(x: 10, y: 10)], smoothingTolerance: 1)
        #expect(!path.isEmpty)
        let bounds = path.bounds
        #expect(bounds.width < 1 && bounds.height < 1)
    }

    @Test("Der geglättete Pfad ist offen, nicht geschlossen")
    func resultIsOpenPath() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 0)]
        let path = FreehandStroke.path(from: points, smoothingTolerance: 0)
        #expect(!path.subpaths[0].isClosed)
    }

    @Test("Anfangs- und Endpunkt bleiben erhalten (Douglas-Peucker entfernt sie nie)")
    func startAndEndAreKept() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 1), CGPoint(x: 10, y: 0), CGPoint(x: 15, y: 1), CGPoint(x: 20, y: 0)]
        let path = FreehandStroke.path(from: points, smoothingTolerance: 100)
        let subpath = path.subpaths[0]
        #expect(subpath.anchors.first?.point == CGPoint(x: 0, y: 0))
        #expect(subpath.anchors.last?.point == CGPoint(x: 20, y: 0))
    }

    @Test("Grössere Glättungstoleranz reduziert die Ankerzahl bei fast gerader Linie")
    func higherToleranceRemovesMorePoints() {
        // Eine fast gerade Linie mit winzigem Zickzack: Bei genügend hoher
        // Toleranz sollte Douglas-Peucker die Zwischenpunkte verwerfen.
        var points: [CGPoint] = []
        for i in 0...20 {
            let x = CGFloat(i) * 5
            let y: CGFloat = i % 2 == 0 ? 0 : 0.1
            points.append(CGPoint(x: x, y: y))
        }
        let precise = FreehandStroke.path(from: points, smoothingTolerance: 0.01)
        let smoothed = FreehandStroke.path(from: points, smoothingTolerance: 5)
        #expect(smoothed.subpaths[0].anchors.count < precise.subpaths[0].anchors.count)
    }

    @Test("Hüllrahmen des geglätteten Pfads bleibt nah an der Punktfolge, überschiesst nicht grob")
    func boundsStayCloseToInputPoints() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)]
        let path = FreehandStroke.path(from: points, smoothingTolerance: 0)
        let bounds = path.bounds
        // Grosszügige Tolereranz nach oben für die Bézier-Rundung an der
        // Spitze, aber keine krasse Entgleisung.
        #expect(bounds.minX >= -5 && bounds.maxX <= 105)
        #expect(bounds.minY >= -5 && bounds.maxY <= 55)
    }

    @Test("Extrem lange Punktfolge (potenziell aus einer sehr langen Zugbewegung) bleibt handhabbar")
    func veryLongPointSequenceStaysBounded() {
        var points: [CGPoint] = []
        for i in 0..<20_000 {
            points.append(CGPoint(x: CGFloat(i) * 0.5, y: CGFloat(i % 7)))
        }
        let path = FreehandStroke.path(from: points, smoothingTolerance: 0.5)
        #expect(!path.isEmpty)
        #expect(path.subpaths[0].anchors.count <= FreehandStroke.maxInputPoints)
    }
}
