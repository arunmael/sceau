import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("BooleanOperator — iOverlay-Anbindung")
struct BooleanOperatorTests {

    // MARK: - Hilfsfunktionen

    /// Achsenausgerichtetes Quadrat als geschlossener Teilpfad aus Eckpunkten.
    private static func square(origin: CGPoint, side: CGFloat) -> VectorPath {
        VectorPath(subpath: Subpath(closedPolygon: [
            CGPoint(x: origin.x, y: origin.y),
            CGPoint(x: origin.x + side, y: origin.y),
            CGPoint(x: origin.x + side, y: origin.y + side),
            CGPoint(x: origin.x, y: origin.y + side)
        ]))
    }

    /// Flächenberechnung per Shoelace-Formel — dient in den Tests sowohl der
    /// Flächenkontrolle als auch der Bestimmung der Umlaufrichtung (Vorzeichen).
    private static func shoelaceArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in 0..<points.count {
            let p0 = points[i]
            let p1 = points[(i + 1) % points.count]
            sum += p0.x * p1.y - p1.x * p0.y
        }
        return sum / 2
    }

    private static func signedArea(of subpath: Subpath) -> CGFloat {
        shoelaceArea(subpath.anchors.map(\.point))
    }

    // MARK: - Tests

    @Test("Vereinigung zweier überlappender Quadrate ergibt die erwartete Fläche")
    func unionOfOverlappingSquares() throws {
        let subject = Self.square(origin: .zero, side: 100)
        let clip = Self.square(origin: CGPoint(x: 50, y: 0), side: 100)

        let result = try BooleanOperator.apply(.union, subject: subject, clip: clip)

        let totalArea = result.subpaths.reduce(CGFloat(0)) { $0 + abs(Self.signedArea(of: $1)) }
        #expect(abs(totalArea - 15000) < 1, "Fläche war \(totalArea)")
    }

    @Test("Schnittmenge zweier überlappender Quadrate ergibt die erwartete Fläche")
    func intersectionOfOverlappingSquares() throws {
        let subject = Self.square(origin: .zero, side: 100)
        let clip = Self.square(origin: CGPoint(x: 50, y: 0), side: 100)

        let result = try BooleanOperator.apply(.intersect, subject: subject, clip: clip)

        let totalArea = result.subpaths.reduce(CGFloat(0)) { $0 + abs(Self.signedArea(of: $1)) }
        #expect(abs(totalArea - 5000) < 1, "Fläche war \(totalArea)")
    }

    @Test("Schnittmenge zweier disjunkter Quadrate wirft emptyResult")
    func intersectionOfDisjointSquaresThrows() {
        let subject = Self.square(origin: .zero, side: 100)
        let clip = Self.square(origin: CGPoint(x: 500, y: 500), side: 100)

        #expect(throws: BooleanError.emptyResult) {
            try BooleanOperator.apply(.intersect, subject: subject, clip: clip)
        }
    }

    @Test("Subtraktion eines zentrierten kleinen Quadrats hinterlässt Aussenkontur und Loch mit entgegengesetzter Umlaufrichtung")
    func subtractCenteredSquareLeavesHole() throws {
        let subject = Self.square(origin: .zero, side: 100)
        let clip = Self.square(origin: CGPoint(x: 30, y: 30), side: 40)

        let result = try BooleanOperator.apply(.subtract, subject: subject, clip: clip)

        #expect(result.subpaths.count == 2, "Aussenkontur + Loch erwartet")

        // Die Netto-Fläche einer Form mit Loch ist die Summe der *vorzeichenbehafteten*
        // Flächen (Aussenkontur positiv, Loch negativ durch entgegengesetzte
        // Umlaufrichtung) — nicht die Summe der Beträge, sonst würde das Loch
        // die Fläche vergrössern statt sie abzuziehen.
        // iOverlay legt die Umlaufrichtung nach seiner eigenen, dokumentierten
        // Konvention fest (Aussenkontur "im Uhrzeigersinn") — wir übernehmen
        // sie unverändert (siehe Doku-Kommentar in BooleanOperator), daher
        // interessiert hier nur der Betrag der Netto-Fläche, nicht ihr
        // absolutes Vorzeichen im Shoelace-Ergebnis dieses Tests.
        let signedAreas = result.subpaths.map(Self.signedArea)
        let totalArea = abs(signedAreas.reduce(0, +))
        #expect(abs(totalArea - 8400) < 1, "Fläche war \(totalArea)")

        let positive = signedAreas.filter { $0 > 0 }.count
        let negative = signedAreas.filter { $0 < 0 }.count
        #expect(positive == 1 && negative == 1, "Aussenkontur und Loch müssen entgegengesetzt umlaufen — Vorzeichen: \(signedAreas)")
    }

    @Test("Ausschliessen (XOR) zweier überlappender Quadrate ergibt die erwartete Fläche")
    func excludeOfOverlappingSquares() throws {
        let subject = Self.square(origin: .zero, side: 100)
        let clip = Self.square(origin: CGPoint(x: 50, y: 0), side: 100)

        let result = try BooleanOperator.apply(.exclude, subject: subject, clip: clip)

        let totalArea = result.subpaths.reduce(CGFloat(0)) { $0 + abs(Self.signedArea(of: $1)) }
        #expect(abs(totalArea - 10000) < 1, "Fläche war \(totalArea)")
    }

    @Test("Selbstüberschneidender Pfad (Achterschleife) als Subjekt stürzt nicht ab")
    func selfIntersectingSubjectDoesNotCrash() throws {
        // Achterschleife: zwei Dreiecke, die sich in der Mitte kreuzen.
        let figureEight = VectorPath(subpath: Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 0, y: 100)
        ]))
        let clip = Self.square(origin: CGPoint(x: 25, y: 25), side: 50)

        // Es geht hier nicht um einen bestimmten Flächenwert, sondern darum,
        // dass die Operation kontrolliert zurückkehrt (Ergebnis oder Fehler)
        // statt abzustürzen.
        do {
            _ = try BooleanOperator.apply(.union, subject: figureEight, clip: clip)
        } catch is BooleanError {
            // Ein kontrollierter Fehler ist ein akzeptables Ergebnis.
        }
    }

    @Test("Leerer Pfad als Eingabe wirft emptyInput")
    func emptyInputThrows() {
        let empty = VectorPath()
        let square = Self.square(origin: .zero, side: 100)

        #expect(throws: BooleanError.emptyInput) {
            try BooleanOperator.apply(.union, subject: empty, clip: square)
        }
        #expect(throws: BooleanError.emptyInput) {
            try BooleanOperator.apply(.union, subject: square, clip: empty)
        }
    }
}
