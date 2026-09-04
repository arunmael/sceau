import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("ViewFitting — Zeichenfläche ins Fenster einpassen")
struct ViewFittingTests {

    @Test("Bei breitem Fenster begrenzt die Höhe den Zoom")
    func heightLimitsInWideViewport() {
        // 1000×1000 in 2000×600 mit 40 Rand: nutzbar sind 1920×520,
        // massgeblich ist also 520/1000.
        let zoom = ViewFitting.zoomToFit(
            artboard: CGSize(width: 1000, height: 1000),
            in: CGSize(width: 2000, height: 600),
            padding: 40
        )
        #expect(abs(zoom - 0.52) < 0.0001, "war \(zoom)")
    }

    @Test("Bei hohem Fenster begrenzt die Breite den Zoom")
    func widthLimitsInTallViewport() {
        let zoom = ViewFitting.zoomToFit(
            artboard: CGSize(width: 1000, height: 1000),
            in: CGSize(width: 600, height: 2000),
            padding: 40
        )
        #expect(abs(zoom - 0.52) < 0.0001, "war \(zoom)")
    }

    @Test("Eine kleine Zeichenfläche wird vergrössert, nicht nur verkleinert")
    func smallArtboardIsEnlarged() {
        // Ein Favicon soll das Fenster ausfüllen, sonst müsste man jedes Mal
        // von Hand hineinzoomen.
        let zoom = ViewFitting.zoomToFit(
            artboard: CGSize(width: 64, height: 64),
            in: CGSize(width: 1000, height: 1000),
            padding: 40
        )
        #expect(zoom > 10, "war \(zoom)")
    }

    @Test("Der Zoom bleibt in den zulässigen Grenzen")
    func zoomStaysWithinLimits() {
        let winzig = ViewFitting.zoomToFit(
            artboard: CGSize(width: 1, height: 1),
            in: CGSize(width: 10000, height: 10000)
        )
        #expect(winzig <= 64)

        let riesig = ViewFitting.zoomToFit(
            artboard: CGSize(width: 1_000_000, height: 1_000_000),
            in: CGSize(width: 100, height: 100)
        )
        #expect(riesig >= 0.05)
    }

    @Test("Entartete Angaben liefern einen brauchbaren Wert statt NaN")
    func degenerateInputsStaySane() {
        let fälle: [(CGSize, CGSize)] = [
            (CGSize(width: 0, height: 0), CGSize(width: 800, height: 600)),
            (CGSize(width: 100, height: 100), CGSize(width: 0, height: 0)),
            (CGSize(width: -50, height: 100), CGSize(width: 800, height: 600)),
            (CGSize(width: CGFloat.nan, height: 100), CGSize(width: 800, height: 600))
        ]

        for (artboard, viewport) in fälle {
            let zoom = ViewFitting.zoomToFit(artboard: artboard, in: viewport)
            #expect(zoom.isFinite, "nicht endlich bei \(artboard) in \(viewport)")
            #expect(zoom > 0, "nicht positiv bei \(artboard) in \(viewport)")
        }
    }

    @Test("Ein Rand kleiner als das Fenster wird berücksichtigt")
    func paddingIsHonoured() {
        let ohneRand = ViewFitting.zoomToFit(
            artboard: CGSize(width: 100, height: 100),
            in: CGSize(width: 500, height: 500),
            padding: 0
        )
        let mitRand = ViewFitting.zoomToFit(
            artboard: CGSize(width: 100, height: 100),
            in: CGSize(width: 500, height: 500),
            padding: 50
        )
        #expect(ohneRand > mitRand)
        #expect(abs(ohneRand - 5) < 0.0001)
        #expect(abs(mitRand - 4) < 0.0001)
    }

    @Test("Ein übergrosser Rand macht das Ergebnis nicht unbrauchbar")
    func oversizedPaddingIsSurvivable() {
        let zoom = ViewFitting.zoomToFit(
            artboard: CGSize(width: 100, height: 100),
            in: CGSize(width: 100, height: 100),
            padding: 500
        )
        #expect(zoom.isFinite)
        #expect(zoom >= 0.05)
    }
}
