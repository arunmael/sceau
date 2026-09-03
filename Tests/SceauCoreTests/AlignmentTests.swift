import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("LayoutOps — Ausrichten und Verteilen")
struct AlignmentTests {

    private func applied(_ rects: [CGRect], _ offsets: [CGVector]) -> [CGRect] {
        zip(rects, offsets).map { $0.offsetBy(dx: $1.dx, dy: $1.dy) }
    }

    @Test("Linksbündig richtet an der linkesten Kante der Auswahl aus")
    func alignLeftUsesSelectionBounds() {
        let rects = [
            CGRect(x: 50, y: 0, width: 10, height: 10),
            CGRect(x: 20, y: 30, width: 40, height: 10),
            CGRect(x: 80, y: 60, width: 10, height: 10)
        ]
        let result = applied(rects, LayoutOps.align(rects, to: .left))

        let allAtLeft = result.allSatisfy { $0.minX == 20 }
        #expect(allAtLeft)
        // Ausrichten darf nur längs einer Achse wirken.
        #expect(result.map(\.minY) == [0, 30, 60])
    }

    @Test("Horizontal zentrieren bezieht sich auf einen übergebenen Bezugsrahmen")
    func centerXWithinContainer() {
        let artboard = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let rects = [CGRect(x: 0, y: 0, width: 100, height: 100)]
        let result = applied(rects, LayoutOps.align(rects, to: .centerX, within: artboard))

        #expect(result[0].midX == 500)
        #expect(result[0].minY == 0, "die andere Achse bleibt unberührt")
    }

    @Test("Unten ausrichten setzt alle auf die unterste Kante")
    func alignBottom() {
        let rects = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 20, y: 0, width: 10, height: 50)
        ]
        let result = applied(rects, LayoutOps.align(rects, to: .bottom))
        let allAtBottom = result.allSatisfy { $0.maxY == 50 }
        #expect(allAtBottom)
    }

    @Test("Verteilen erzeugt gleich grosse Lücken zwischen ungleich breiten Objekten")
    func distributeCreatesEqualGaps() {
        // Breiten 10, 40, 10 auf der Strecke 0…100: belegt 60, bleiben 40 für
        // zwei Lücken, also je 20.
        let rects = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 35, y: 0, width: 40, height: 10),
            CGRect(x: 90, y: 0, width: 10, height: 10)
        ]
        let result = applied(rects, LayoutOps.distribute(rects, along: .horizontal))

        #expect(result[0].minX == 0, "äussere Objekte bleiben stehen")
        #expect(result[2].minX == 90, "äussere Objekte bleiben stehen")
        let gapLeft = result[1].minX - result[0].maxX
        let gapRight = result[2].minX - result[1].maxX
        #expect(abs(gapLeft - gapRight) < 0.0001, "links \(gapLeft), rechts \(gapRight)")
        #expect(abs(gapLeft - 20) < 0.0001)
    }

    @Test("Verteilen ordnet die Verschiebungen der ursprünglichen Reihenfolge zu")
    func distributeRespectsInputOrder() {
        // Bewusst unsortiert übergeben: das Ergebnis muss trotzdem positionsweise passen.
        let rects = [
            CGRect(x: 90, y: 0, width: 10, height: 10),
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 35, y: 0, width: 40, height: 10)
        ]
        let offsets = LayoutOps.distribute(rects, along: .horizontal)

        #expect(offsets[0] == .zero, "der rechte Rand bleibt stehen")
        #expect(offsets[1] == .zero, "der linke Rand bleibt stehen")
        #expect(offsets[2] != .zero, "nur das mittlere Objekt bewegt sich")
    }

    @Test("Weniger als drei Objekte ergeben keine Verschiebung")
    func distributeNeedsThree() {
        let rects = [CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 50, y: 0, width: 10, height: 10)]
        let allZero = LayoutOps.distribute(rects, along: .horizontal).allSatisfy { $0 == .zero }
        #expect(allZero)
    }

    @Test("Leere Eingabe bleibt harmlos")
    func emptyInputIsSafe() {
        #expect(LayoutOps.align([], to: .left).isEmpty)
        #expect(LayoutOps.distribute([], along: .vertical).isEmpty)
    }

    @Test("Vertikal verteilen wirkt auf y statt auf x")
    func distributeVertical() {
        let rects = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 0, y: 33, width: 10, height: 10),
            CGRect(x: 0, y: 90, width: 10, height: 10)
        ]
        let result = applied(rects, LayoutOps.distribute(rects, along: .vertical))
        let gapTop = result[1].minY - result[0].maxY
        let gapBottom = result[2].minY - result[1].maxY

        #expect(abs(gapTop - gapBottom) < 0.0001)
        let xUnchanged = result.allSatisfy { $0.minX == 0 }
        #expect(xUnchanged)
    }
}
