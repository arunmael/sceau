import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SceauCore

/// Anzeige von Fotos auf der Zeichenfläche (Problems: „laggy mit vielen
/// Fotos"). Die Zeichenfläche baut bei jeder Änderung neu auf — Bilder
/// dürfen dabei weder jedes Mal neu dekodiert noch in voller Auflösung
/// dekodiert werden, wenn sie nur klein zu sehen sind.
@Suite("Bildanzeige — Auflösungsstufen")
struct DisplayImageResolutionTests {

    @Test("Wird das Bild grösser angezeigt, als es ist, bleibt es in voller Auflösung")
    func upscaledUsesFullResolution() {
        let size = DisplayImageResolution.maxPixelSize(
            imagePixelSize: CGSize(width: 400, height: 300),
            displaySize: CGSize(width: 800, height: 600)
        )
        #expect(size == nil)
    }

    @Test("Verkleinert wird auf die nächste Zweierpotenz über dem Bedarf")
    func roundsUpToPowerOfTwo() {
        let size = DisplayImageResolution.maxPixelSize(
            imagePixelSize: CGSize(width: 4000, height: 3000),
            displaySize: CGSize(width: 400, height: 300)
        )
        #expect(size == 512)
    }

    @Test("Kleine Zoomänderungen bleiben in derselben Stufe")
    func nearbyZoomSharesBucket() {
        let image = CGSize(width: 4000, height: 3000)
        let a = DisplayImageResolution.maxPixelSize(imagePixelSize: image, displaySize: CGSize(width: 300, height: 225))
        let b = DisplayImageResolution.maxPixelSize(imagePixelSize: image, displaySize: CGSize(width: 500, height: 375))
        #expect(a == 512)
        #expect(b == 512)
    }

    @Test("Verzerrt eingepasst zählt die stärker vergrösserte Achse")
    func stretchedUsesLargerAxisScale() {
        // Breite 4000 → 400 (0,1), Höhe 1000 → 400 (0,4): die Höhe braucht
        // mehr Pixel, also längste Seite 4000 · 0,4 = 1600 → Stufe 2048.
        let size = DisplayImageResolution.maxPixelSize(
            imagePixelSize: CGSize(width: 4000, height: 1000),
            displaySize: CGSize(width: 400, height: 400)
        )
        #expect(size == 2048)
    }

    @Test("Reicht die Stufe an die Originalgrösse heran, wird nicht verkleinert")
    func bucketAtOrAboveOriginalIsFullResolution() {
        let size = DisplayImageResolution.maxPixelSize(
            imagePixelSize: CGSize(width: 4000, height: 3000),
            displaySize: CGSize(width: 3000, height: 2250)
        )
        #expect(size == nil)
    }

    @Test("Winzige Anzeige fällt nicht unter die Mindeststufe")
    func tinyDisplayHasMinimumBucket() {
        let size = DisplayImageResolution.maxPixelSize(
            imagePixelSize: CGSize(width: 4000, height: 3000),
            displaySize: CGSize(width: 2, height: 1.5)
        )
        #expect(size == DisplayImageResolution.minimumPixelSize)
    }

    @Test("Entartete Grössen stürzen nicht ab")
    func degenerateSizes() {
        #expect(DisplayImageResolution.maxPixelSize(imagePixelSize: .zero, displaySize: CGSize(width: 10, height: 10)) == nil)
        #expect(DisplayImageResolution.maxPixelSize(
            imagePixelSize: CGSize(width: 4000, height: 3000),
            displaySize: .zero
        ) == DisplayImageResolution.minimumPixelSize)
    }
}

@MainActor
@Suite("Bildanzeige — Dekodier-Cache")
struct DecodedImageCacheTests {

    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test("Dieselben Bilddaten werden nur einmal dekodiert")
    func sameDataDecodedOnce() throws {
        let cache = DecodedImageCache()
        let data = try pngData(width: 100, height: 80)
        let copy = data  // wie im Dokument: Undo-Stände teilen sich den Puffer

        let first = try #require(cache.image(for: data, displaySize: CGSize(width: 100, height: 80)))
        let second = try #require(cache.image(for: copy, displaySize: CGSize(width: 100, height: 80)))

        #expect(first === second)
        #expect(cache.decodeCount == 1)
    }

    @Test("Inhaltsgleiche Daten aus getrenntem Puffer treffen ebenfalls")
    func equalContentSeparateBuffer() throws {
        let cache = DecodedImageCache()
        let data = try pngData(width: 100, height: 80)
        let separate = Data(Array(data))

        let first = cache.image(for: data, displaySize: CGSize(width: 100, height: 80))
        let second = cache.image(for: separate, displaySize: CGSize(width: 100, height: 80))

        #expect(first != nil)
        #expect(first === second)
        #expect(cache.decodeCount == 1)
    }

    @Test("Verschiedene Bilder werden getrennt dekodiert")
    func differentDataDecodedSeparately() throws {
        let cache = DecodedImageCache()
        let a = try pngData(width: 100, height: 80)
        let b = try pngData(width: 90, height: 80)

        let imageA = try #require(cache.image(for: a, displaySize: CGSize(width: 100, height: 80)))
        let imageB = try #require(cache.image(for: b, displaySize: CGSize(width: 90, height: 80)))

        #expect(imageA.width == 100)
        #expect(imageB.width == 90)
        #expect(cache.decodeCount == 2)
    }

    @Test("Klein angezeigte Bilder werden verkleinert dekodiert")
    func downsamplesForSmallDisplay() throws {
        let cache = DecodedImageCache()
        let data = try pngData(width: 2000, height: 1500)

        let image = try #require(cache.image(for: data, displaySize: CGSize(width: 200, height: 150)))

        #expect(max(image.width, image.height) == 256)
        #expect(image.width == 256)
        #expect(image.height == 192)
    }

    @Test("Gross angezeigte Bilder bleiben in voller Auflösung")
    func fullResolutionWhenLarge() throws {
        let cache = DecodedImageCache()
        let data = try pngData(width: 300, height: 200)

        let image = try #require(cache.image(for: data, displaySize: CGSize(width: 900, height: 600)))

        #expect(image.width == 300)
        #expect(image.height == 200)
    }

    @Test("Zoom innerhalb der Stufe dekodiert nicht neu, über die Stufe hinaus schon")
    func redecodesOnlyWhenBucketChanges() throws {
        let cache = DecodedImageCache()
        let data = try pngData(width: 2000, height: 1500)

        _ = cache.image(for: data, displaySize: CGSize(width: 150, height: 112.5))
        _ = cache.image(for: data, displaySize: CGSize(width: 200, height: 150))
        #expect(cache.decodeCount == 1)

        let larger = try #require(cache.image(for: data, displaySize: CGSize(width: 600, height: 450)))
        #expect(cache.decodeCount == 2)
        #expect(larger.width == 1024)
    }

    @Test("Aufräumen entfernt nur, was seit dem letzten Aufräumen unbenutzt blieb")
    func purgeRemovesUnused() throws {
        let cache = DecodedImageCache()
        let kept = try pngData(width: 100, height: 80)
        let dropped = try pngData(width: 90, height: 80)

        _ = cache.image(for: kept, displaySize: CGSize(width: 100, height: 80))
        _ = cache.image(for: dropped, displaySize: CGSize(width: 90, height: 80))
        cache.purgeUnused()
        #expect(cache.count == 2)

        _ = cache.image(for: kept, displaySize: CGSize(width: 100, height: 80))
        cache.purgeUnused()
        #expect(cache.count == 1)

        _ = cache.image(for: kept, displaySize: CGSize(width: 100, height: 80))
        #expect(cache.decodeCount == 2)
    }

    @Test("Ungültige Daten ergeben kein Bild")
    func invalidData() {
        let cache = DecodedImageCache()
        #expect(cache.image(for: Data([1, 2, 3, 4]), displaySize: CGSize(width: 10, height: 10)) == nil)
        #expect(cache.image(for: Data(), displaySize: CGSize(width: 10, height: 10)) == nil)
    }
}
