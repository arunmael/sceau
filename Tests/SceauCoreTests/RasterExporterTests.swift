import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SceauCore

/// Prüft `RasterExporter`/`PDFExporter` gegen echte Leser (`CGImageSource`,
/// `CGPDFDocument`), nicht gegen die eigene Schreiblogik — siehe
/// `agent-rules.md` Abschnitt 4: Export-Korrektheit hat Vorrang, und eine
/// Selbstprüfung würde einen systematischen Fehler (z. B. eine fehlende
/// Spiegelung) nicht aufdecken.
@Suite("RasterExporter")
struct RasterExporterTests {

    /// Ein Dokument, dessen rotes Rechteck nur die **obere** Hälfte
    /// (Dokumentkoordinaten y = 0…50) der 100×100-Fläche bedeckt.
    private func topHalfRedDocument(background: RGBAColor = .clear) -> Document {
        var document = Document(artboard: Artboard(size: CGSize(width: 100, height: 100), background: background))
        var style = Style()
        style.fill = .solid(RGBAColor(red: 1, green: 0, blue: 0))
        style.stroke = nil
        document.nodes = [
            Node(
                name: "Oben",
                style: style,
                content: .shape(.rectangle(frame: CGRect(x: 0, y: 0, width: 100, height: 50), cornerRadius: 0))
            )
        ]
        return document
    }

    /// Liest die RGBA-Bytes eines PNG per ImageIO zurück, ohne AppKit.
    private func pixels(of data: Data, width: Int, height: Int) throws -> [UInt8] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            Issue.record("PNG liess sich nicht über ImageIO einlesen")
            return []
        }
        #expect(image.width == width)
        #expect(image.height == height)

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Referenzkontext liess sich nicht anlegen")
            return []
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    /// Liefert das Pixel (RGBA, 0…255) an einer Bildkoordinate (Ursprung
    /// links oben — die übliche Bitmap-Konvention, wie sie `CGImage` liefert).
    private func pixel(_ buffer: [UInt8], x: Int, y: Int, width: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let offset = (y * width + x) * 4
        return (buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3])
    }

    @Test("Spiegelung: die obere Dokumenthälfte landet oben im Bild, nicht unten")
    func mirroringPlacesTopHalfAtImageTop() throws {
        let document = topHalfRedDocument()
        let data = try RasterExporter.pngData(document, pixelWidth: 100, pixelHeight: 100)
        let buffer = try pixels(of: data, width: 100, height: 100)

        // Bildkoordinate (50,10): oberer Bereich des Bildes — muss die
        // Dokument-y=10-Zeile zeigen, die innerhalb des roten Rechtecks liegt.
        let top = pixel(buffer, x: 50, y: 10, width: 100)
        #expect(top.r == 255)
        #expect(top.g == 0)
        #expect(top.b == 0)
        #expect(top.a == 255)

        // Bildkoordinate (50,90): unterer Bereich, ausserhalb des Rechtecks —
        // muss durchsichtig bleiben. Stünde der Export auf dem Kopf, wäre
        // genau hier das Rot zu finden statt bei y=10.
        let bottom = pixel(buffer, x: 50, y: 90, width: 100)
        #expect(bottom.a == 0)
    }

    @Test("PNG hat exakt die angeforderte Pixelgrösse")
    func pngHasRequestedSize() throws {
        let document = Document.empty(preset: .favicon)
        let data = try RasterExporter.pngData(document, pixelWidth: 48, pixelHeight: 96)
        let buffer = try pixels(of: data, width: 48, height: 96)
        #expect(buffer.count == 48 * 96 * 4)
    }

    @Test("Transparenter Hintergrund bleibt transparent")
    func transparentBackgroundStaysTransparent() throws {
        let document = topHalfRedDocument(background: .clear)
        let data = try RasterExporter.pngData(document, pixelWidth: 100, pixelHeight: 100)
        let buffer = try pixels(of: data, width: 100, height: 100)

        let freeSpot = pixel(buffer, x: 5, y: 95, width: 100)
        #expect(freeSpot.a == 0)
    }

    @Test("Nicht transparenter Hintergrund wird gefüllt")
    func opaqueBackgroundIsFilled() throws {
        let document = topHalfRedDocument(background: RGBAColor(red: 0, green: 0, blue: 1))
        let data = try RasterExporter.pngData(document, pixelWidth: 100, pixelHeight: 100)
        let buffer = try pixels(of: data, width: 100, height: 100)

        let freeSpot = pixel(buffer, x: 5, y: 95, width: 100)
        #expect(freeSpot.a == 255)
        #expect(freeSpot.b == 255)
    }

    @Test("Unsichtbare Knoten erscheinen nicht im Bild")
    func invisibleNodesAreSkipped() throws {
        var document = topHalfRedDocument()
        document.nodes[0].isVisible = false
        let data = try RasterExporter.pngData(document, pixelWidth: 100, pixelHeight: 100)
        let buffer = try pixels(of: data, width: 100, height: 100)

        let top = pixel(buffer, x: 50, y: 10, width: 100)
        #expect(top.a == 0)
    }

    @Test("iconSet liefert sortierte Ergebnisse in den richtigen Grössen")
    func iconSetProducesSortedSizes() throws {
        let document = Document.empty(preset: .favicon)
        let results = try RasterExporter.iconSet(document, sizes: [64, 16, 32])

        #expect(results.map(\.size) == [16, 32, 64])

        for entry in results {
            let buffer = try pixels(of: entry.data, width: entry.size, height: entry.size)
            #expect(buffer.count == entry.size * entry.size * 4)
        }
    }

    @Test("Ungültige Grössen werfen invalidSize statt abzustürzen")
    func invalidSizesThrow() {
        let document = Document.empty(preset: .favicon)

        #expect(throws: ExportError.invalidSize) {
            _ = try RasterExporter.pngData(document, pixelWidth: 0, pixelHeight: 10)
        }
        #expect(throws: ExportError.invalidSize) {
            _ = try RasterExporter.pngData(document, pixelWidth: 10, pixelHeight: -1)
        }
        #expect(throws: ExportError.invalidSize) {
            _ = try RasterExporter.iconSet(document, sizes: [16, 0])
        }
    }
}

@Suite("PDFExporter")
struct PDFExporterTests {

    @Test("PDF lässt sich mit CGPDFDocument einlesen, genau eine Seite in Zeichenflächengrösse")
    func pdfReadsBackWithCorrectPage() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 200, height: 120)))
        document.nodes = [
            Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 50, height: 50), cornerRadius: 0))
        ]

        let data = try PDFExporter.pdfData(document)

        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider)
        else {
            Issue.record("PDF liess sich nicht über CGPDFDocument einlesen")
            return
        }

        #expect(pdf.numberOfPages == 1)

        guard let page = pdf.page(at: 1) else {
            Issue.record("PDF hat keine erste Seite")
            return
        }
        let mediaBox = page.getBoxRect(CGPDFBox.mediaBox)
        #expect(mediaBox.width == 200)
        #expect(mediaBox.height == 120)
    }

    // MARK: - Sichere Pixel-Umrechnung

    @Test("Normaler Fall: Punkte mal Skalierung, gerundet")
    func safePixelLengthNormalCase() {
        #expect(RasterExporter.safePixelLength(100, scale: 2) == 200)
        #expect(RasterExporter.safePixelLength(33.4, scale: 1) == 33)
    }

    @Test("Nicht endliche oder nicht positive Werte fallen auf 1 Pixel zurück statt zu crashen")
    func safePixelLengthHandlesNonFiniteAndNonPositive() {
        #expect(RasterExporter.safePixelLength(.infinity, scale: 1) == 1)
        #expect(RasterExporter.safePixelLength(.nan, scale: 1) == 1)
        #expect(RasterExporter.safePixelLength(-50, scale: 1) == 1)
        #expect(RasterExporter.safePixelLength(0, scale: 1) == 1)
        #expect(RasterExporter.safePixelLength(100, scale: .infinity) == 1)
    }

    @Test("Absurd grosse Zeichenflächen werden auf ein handhabbares Maximum gekappt")
    func safePixelLengthClampsHugeValues() {
        #expect(RasterExporter.safePixelLength(1_000_000, scale: 100) == 16384)
    }
}
