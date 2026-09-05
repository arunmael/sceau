import CoreGraphics
import Testing

@testable import SceauCore

@Suite("ProportionalResize — Seitenverhältnis beim Ziehen sperren")
struct ProportionalResizeTests {

    @Test("Breite treibt: grösserer horizontaler Ausschlag bestimmt den Rahmen")
    func widthGoverns() {
        // Seitenverhältnis 2:1. dx=150 verlangt (bei diesem Verhältnis) eine
        // Höhe von 75 — mehr als das von dy=40 verlangte Mass (40) — die Breite
        // gewinnt also.
        let anchor = CGPoint(x: 0, y: 0)
        let drag = CGPoint(x: 150, y: 40)
        let rect = ProportionalResize.lockedRect(anchor: anchor, dragPoint: drag, aspectRatio: 2)

        #expect(abs(rect.width - 150) < 0.001)
        #expect(abs(rect.height - 75) < 0.001)
    }

    @Test("Höhe treibt: grösserer vertikaler Ausschlag bestimmt den Rahmen")
    func heightGoverns() {
        let anchor = CGPoint(x: 0, y: 0)
        let drag = CGPoint(x: 40, y: 150)
        let rect = ProportionalResize.lockedRect(anchor: anchor, dragPoint: drag, aspectRatio: 2)

        #expect(abs(rect.height - 150) < 0.001)
        #expect(abs(rect.width - 300) < 0.001)
    }

    @Test("Vorzeichen der Zugrichtung bestimmt die Quadrantenlage, Anker bleibt fix")
    func signDeterminesQuadrant() {
        let anchor = CGPoint(x: 100, y: 100)
        let drag = CGPoint(x: 20, y: 70) // links und oberhalb des Ankers
        let rect = ProportionalResize.lockedRect(anchor: anchor, dragPoint: drag, aspectRatio: 1)

        // Anker bleibt eine Ecke des Ergebnisrahmens.
        #expect(abs(rect.maxX - anchor.x) < 0.001)
        #expect(abs(rect.maxY - anchor.y) < 0.001)
        #expect(rect.minX < anchor.x)
        #expect(rect.minY < anchor.y)
    }

    @Test("Seitenverhältnis 1:1 ergibt stets ein Quadrat")
    func squareAspectRatioAlwaysProducesSquare() {
        let anchor = CGPoint.zero
        for drag in [CGPoint(x: 50, y: 10), CGPoint(x: 10, y: 50), CGPoint(x: -30, y: 90)] {
            let rect = ProportionalResize.lockedRect(anchor: anchor, dragPoint: drag, aspectRatio: 1)
            #expect(abs(rect.width - rect.height) < 0.001)
        }
    }

    @Test("Ungültiges Seitenverhältnis (<=0 oder nicht endlich) liefert den freien Rahmen unverändert zurück")
    func invalidAspectRatioFallsBackToFreeRect() {
        let anchor = CGPoint.zero
        let drag = CGPoint(x: 40, y: 90)
        for invalid: CGFloat in [0, -1, .nan, .infinity] {
            let rect = ProportionalResize.lockedRect(anchor: anchor, dragPoint: drag, aspectRatio: invalid)
            #expect(abs(rect.width - 40) < 0.001)
            #expect(abs(rect.height - 90) < 0.001)
        }
    }
}
