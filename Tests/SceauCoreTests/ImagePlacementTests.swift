import CoreGraphics
import Testing

@testable import SceauCore

@Suite("ImagePlacement — Rahmen für ein neu eingesetztes Bild")
struct ImagePlacementTests {

    @Test("Ein kleines Bild wird unskaliert um den Zielpunkt zentriert")
    func smallImageIsCenteredUnscaled() {
        let frame = ImagePlacement.frame(
            forPixelSize: CGSize(width: 40, height: 20),
            centeredAt: CGPoint(x: 100, y: 100),
            maxDimension: 500
        )
        #expect(frame == CGRect(x: 80, y: 90, width: 40, height: 20))
    }

    @Test("Ein zu grosses Bild wird auf die Höchstgrösse herunterskaliert, Seitenverhältnis bleibt erhalten")
    func oversizedImageIsScaledDownPreservingAspectRatio() {
        let frame = ImagePlacement.frame(
            forPixelSize: CGSize(width: 4000, height: 2000),
            centeredAt: .zero,
            maxDimension: 400
        )
        #expect(frame.width == 400)
        #expect(frame.height == 200)
        // Weiterhin um den Zielpunkt zentriert.
        #expect(frame.midX == 0)
        #expect(frame.midY == 0)
    }

    @Test("Eine entartete Pixelgrösse ergibt einen leeren Rahmen statt NaN")
    func degeneratePixelSizeIsSafe() {
        let frame = ImagePlacement.frame(
            forPixelSize: CGSize(width: 0, height: 0),
            centeredAt: CGPoint(x: 10, y: 10),
            maxDimension: 100
        )
        #expect(frame.isEmpty)
    }
}
