import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("Snapper — Einrasten an Kanten, Mitten und Raster")
struct SnappingTests {

    /// Weit entfernte Zeichenfläche, damit sie in Tests, die sich auf Objekte
    /// oder das Raster konzentrieren, nicht ungewollt mit hineinspielt.
    private let farArtboard = CGRect(x: -10_000, y: -10_000, width: 100, height: 100)

    @Test("3 pt neben einer linken Kante rastet bei Toleranz 6 exakt darauf ein")
    func snapsToNearLeftEdge() {
        let target = CGRect(x: 100, y: 0, width: 50, height: 50)
        let moving = CGRect(x: 103, y: 200, width: 10, height: 20)
        let settings = SnapSettings(gridSize: nil, snapsToObjects: true, threshold: 6)

        let result = Snapper.snap(rect: moving, to: [target], within: farArtboard, settings: settings)

        #expect(result.offset == CGVector(dx: -3, dy: 0))
        #expect(result.guides.count == 1)
        #expect(result.guides[0].orientation == .vertical)
        #expect(result.guides[0].position == 100)
    }

    @Test("9 pt Abstand bleibt bei Toleranz 6 ohne Wirkung")
    func outOfRangeDoesNothing() {
        let target = CGRect(x: 100, y: 0, width: 50, height: 50)
        let moving = CGRect(x: 109, y: 200, width: 8, height: 20)
        let settings = SnapSettings(gridSize: nil, snapsToObjects: true, threshold: 6)

        let result = Snapper.snap(rect: moving, to: [target], within: farArtboard, settings: settings)

        #expect(result == .none)
    }

    @Test("Mitte rastet auf Mitte ein")
    func snapsCenterToCenter() {
        let target = CGRect(x: 0, y: 0, width: 100, height: 100) // Mitte 50, 50
        let moving = CGRect(x: 46, y: 46, width: 10, height: 10) // Mitte 51, 51
        let settings = SnapSettings(gridSize: nil, snapsToObjects: true, threshold: 6)

        let result = Snapper.snap(rect: moving, to: [target], within: farArtboard, settings: settings)

        #expect(result.offset == CGVector(dx: -1, dy: -1))
    }

    @Test("x und y rasten unabhängig voneinander ein")
    func axesSnapIndependently() {
        let target = CGRect(x: 100, y: 500, width: 50, height: 50)
        // x liegt weit ausserhalb der Reichweite, nur y kommt in Frage.
        let moving = CGRect(x: 900, y: 503, width: 20, height: 10)
        let settings = SnapSettings(gridSize: nil, snapsToObjects: true, threshold: 6)

        let result = Snapper.snap(rect: moving, to: [target], within: farArtboard, settings: settings)

        #expect(result.offset.dx == 0)
        #expect(result.offset.dy == -3)
        #expect(result.guides.count == 1)
        #expect(result.guides[0].orientation == .horizontal)
    }

    @Test("Ohne Zielobjekte rastet ein Rahmen aufs Raster, ohne Hilfslinie")
    func snapsToGridWithoutGuide() {
        let moving = CGRect(x: 13, y: 13, width: 20, height: 20)
        let settings = SnapSettings(gridSize: 8, snapsToObjects: true, threshold: 6)

        let result = Snapper.snap(rect: moving, to: [], within: farArtboard, settings: settings)

        #expect(result.guides.isEmpty)
        #expect(result.offset.dx != 0 || result.offset.dy != 0)
    }

    @Test("Objektkante hat Vorrang vor dem Raster, wenn beide in Reichweite liegen")
    func objectEdgeBeatsGrid() {
        // Kante bei x=100 (Abstand 2) und Rasterlinie bei x=104 (Abstand 2) liegen
        // beide in Reichweite — die Kante gewinnt trotzdem.
        let target = CGRect(x: 100, y: 0, width: 10, height: 10)
        let moving = CGRect(x: 102, y: 200, width: 20, height: 20)
        let settings = SnapSettings(gridSize: 8, snapsToObjects: true, threshold: 6)

        let result = Snapper.snap(rect: moving, to: [target], within: farArtboard, settings: settings)

        #expect(result.offset.dx == -2)
        #expect(result.guides.count == 1)
    }

    @Test("Die Zeichenflächenmitte ist ein gültiges Ziel")
    func snapsToArtboardCenter() {
        let artboard = CGRect(x: 0, y: 0, width: 1000, height: 1000) // Mitte 500, 500
        let moving = CGRect(x: 480, y: 480, width: 40, height: 40) // Mitte 500, 500 exakt
        let settings = SnapSettings(gridSize: nil, snapsToObjects: false, threshold: 6)

        let result = Snapper.snap(rect: moving, to: [], within: artboard, settings: settings)

        #expect(result.offset == .zero)
        #expect(result.guides.count == 2)
    }

    @Test("Es wird stets die nächstliegende Kante gewählt")
    func picksNearestCandidate() {
        let near = CGRect(x: 100, y: 0, width: 10, height: 10) // Kante bei 100, Abstand 2
        let far = CGRect(x: 80, y: 0, width: 10, height: 10) // alle Bezugswerte ausser Reichweite
        let moving = CGRect(x: 102, y: 200, width: 20, height: 20)
        let settings = SnapSettings(gridSize: nil, snapsToObjects: true, threshold: 6)

        let result = Snapper.snap(rect: moving, to: [near, far], within: farArtboard, settings: settings)

        #expect(result.offset.dx == -2)
    }

    @Test("snap(point:) rastet auf Kanten, Mitten und Raster")
    func pointSnapsToEdgesMidpointsAndGrid() {
        let target = CGRect(x: 100, y: 100, width: 50, height: 50) // midX 125
        let settings = SnapSettings(gridSize: nil, snapsToObjects: true, threshold: 6)

        let onEdge = Snapper.snap(point: CGPoint(x: 103, y: 300), to: [target], within: farArtboard, settings: settings)
        #expect(onEdge.offset == CGVector(dx: -3, dy: 0))

        let onCenter = Snapper.snap(point: CGPoint(x: 123, y: 300), to: [target], within: farArtboard, settings: settings)
        #expect(onCenter.offset == CGVector(dx: 2, dy: 0))

        let gridSettings = SnapSettings(gridSize: 10, snapsToObjects: true, threshold: 6)
        let onGrid = Snapper.snap(point: CGPoint(x: 803, y: 300), to: [], within: farArtboard, settings: gridSettings)
        #expect(onGrid.offset == CGVector(dx: -3, dy: 0))
        #expect(onGrid.guides.isEmpty)
    }

    @Test("Leere Ziele, threshold 0 und gridSize 0 stürzen nicht ab")
    func degenerateInputsDoNotCrash() {
        let moving = CGRect(x: 10, y: 10, width: 5, height: 5)

        let emptyTargets = Snapper.snap(
            rect: moving, to: [], within: farArtboard,
            settings: SnapSettings(gridSize: nil, snapsToObjects: true, threshold: 6)
        )
        #expect(emptyTargets == .none)

        let zeroThreshold = Snapper.snap(
            rect: moving, to: [CGRect(x: 50, y: 50, width: 10, height: 10)], within: farArtboard,
            settings: SnapSettings(gridSize: 8, snapsToObjects: true, threshold: 0)
        )
        #expect(zeroThreshold == .none)

        let zeroGrid = Snapper.snap(
            rect: moving, to: [], within: farArtboard,
            settings: SnapSettings(gridSize: 0, snapsToObjects: true, threshold: 6)
        )
        #expect(zeroGrid == .none)

        let degenerateRect = Snapper.snap(
            rect: CGRect(x: 10, y: 10, width: 0, height: 0), to: [CGRect(x: 10, y: 10, width: 0, height: 0)],
            within: farArtboard, settings: SnapSettings(gridSize: 8, snapsToObjects: true, threshold: 6)
        )
        #expect(degenerateRect.offset == .zero)
    }
}
