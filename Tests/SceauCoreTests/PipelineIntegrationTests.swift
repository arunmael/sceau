import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SceauCore

/// Durchstich über die gesamte Kette: Formen anlegen, boolesch verknüpfen,
/// sichern und wieder laden, in alle drei Formate exportieren.
///
/// Die Einzelbausteine sind je für sich getestet; hier geht es um das
/// Zusammenspiel — genau die Stelle, an der Konventionsfehler (Y-Richtung,
/// Umlaufsinn, Farbraum) auffallen, die in isolierten Tests durchrutschen.
@Suite("Durchstich — vom Dokument zum Export")
struct PipelineIntegrationTests {

    /// Baut ein Logo aus einem Kreis, aus dem ein Quadrat herausgeschnitten wird.
    private func makeLogo() throws -> Document {
        var document = Document(artboard: Artboard(size: CGSize(width: 200, height: 200)))

        let circle = Node(shape: .ellipse(frame: CGRect(x: 20, y: 20, width: 160, height: 160)))
        let notch = Node(shape: .rectangle(frame: CGRect(x: 80, y: 80, width: 40, height: 40), cornerRadius: 0))

        let result = try BooleanOperator.apply(
            .subtract,
            subject: NodeGeometry.path(for: circle),
            clip: NodeGeometry.path(for: notch)
        )

        var style = Style()
        style.fill = .solid(RGBAColor(red: 1, green: 0, blue: 0))
        document.nodes = [Node(name: "Logo", style: style, content: .path(result))]
        return document
    }

    @Test("Subtraktion erzeugt eine Aussenkontur mit Loch")
    func subtractProducesHole() throws {
        let document = try makeLogo()
        guard case let .path(path) = document.nodes[0].content else {
            Issue.record("Erwartet wurde ein Pfadknoten")
            return
        }
        #expect(path.subpaths.count == 2, "Aussenkontur plus Loch")

        // Beide Ringe müssen entgegengesetzt umlaufen, sonst wäre das Loch keins.
        let signs = path.subpaths.map { subpath -> Double in
            let points = subpath.anchors.map(\.point)
            var sum = 0.0
            for index in points.indices {
                let a = points[index]
                let b = points[(index + 1) % points.count]
                sum += Double(a.x * b.y - b.x * a.y)
            }
            return sum
        }
        #expect(signs.filter { $0 > 0 }.count == 1)
        #expect(signs.filter { $0 < 0 }.count == 1)
    }

    @Test("JSON-Rundreise über das Dateiformat erhält das Dokument")
    func documentSurvivesFileRoundTrip() throws {
        let document = try makeLogo()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let restored = try JSONDecoder().decode(Document.self, from: data)

        #expect(restored == document)
        #expect(restored.formatVersion == Document.currentFormatVersion)
    }

    @Test("SVG-Export ist wohlgeformt und behält die Ausrichtung")
    func svgExportIsWellFormedAndUpright() throws {
        var document = try makeLogo()
        // Ein Balken ausschliesslich in der oberen Hälfte dient als Referenz.
        var barStyle = Style()
        barStyle.fill = .solid(RGBAColor(red: 0, green: 0, blue: 1))
        document.nodes.append(
            Node(
                name: "Balken",
                style: barStyle,
                content: .shape(.rectangle(frame: CGRect(x: 0, y: 0, width: 200, height: 20), cornerRadius: 0))
            )
        )

        let svg = SVGExporter.export(document)
        _ = try XMLDocument(xmlString: svg, options: [.nodePreserveWhitespace])

        #expect(svg.contains("viewBox=\"0 0 200 200\""))
        // Der Balken liegt im Dokument oben; ohne Spiegelung muss er auch im
        // SVG bei kleinem y stehen.
        #expect(svg.contains("M0,0") || svg.contains("M0 0"), "Balken beginnt oben links:\n\(svg.prefix(600))")
    }

    @Test("PNG-Export trifft die Farben und steht richtig herum")
    func pngExportHasCorrectPixels() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 100, height: 100)))
        var style = Style()
        style.fill = .solid(RGBAColor(red: 1, green: 0, blue: 0))
        document.nodes = [
            Node(
                name: "Oben",
                style: style,
                content: .shape(.rectangle(frame: CGRect(x: 0, y: 0, width: 100, height: 50), cornerRadius: 0))
            )
        ]

        let data = try RasterExporter.pngData(document, pixelWidth: 100, pixelHeight: 100)
        let pixels = try readPixels(data, width: 100, height: 100)

        let top = pixels(50, 10)
        let bottom = pixels(50, 90)

        #expect(top.r == 255 && top.g == 0 && top.b == 0, "oben erwartet rot, war \(top)")
        #expect(bottom.a == 0, "unten erwartet durchsichtig, war \(bottom)")
    }

    @Test("Icon-Satz liefert alle Grössen in einem Durchgang")
    func iconSetProducesAllSizes() throws {
        let document = try makeLogo()
        let icons = try RasterExporter.iconSet(document, sizes: [16, 32, 64, 128, 256, 512, 1024])

        #expect(icons.map(\.size) == [16, 32, 64, 128, 256, 512, 1024])
        let allNonEmpty = icons.allSatisfy { !$0.data.isEmpty }
        #expect(allNonEmpty)
    }

    @Test("PDF-Export lässt sich von einem echten Leser wieder öffnen")
    func pdfExportIsReadable() throws {
        let document = try makeLogo()
        let data = try PDFExporter.pdfData(document)

        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider)
        else {
            Issue.record("PDF liess sich nicht öffnen")
            return
        }
        #expect(pdf.numberOfPages == 1)

        guard let page = pdf.page(at: 1) else {
            Issue.record("Seite 1 fehlt")
            return
        }
        let box = page.getBoxRect(.mediaBox)
        #expect(box.width == 200)
        #expect(box.height == 200)
    }

    // MARK: - Hilfe

    private struct Pixel: CustomStringConvertible {
        let r, g, b, a: UInt8
        var description: String { "rgba(\(r),\(g),\(b),\(a))" }
    }

    /// Liest ein PNG zurück in einen Pixelpuffer — die Prüfung läuft damit
    /// gegen einen echten Decoder statt gegen den eigenen Schreiber.
    ///
    /// Der Bitmap-Puffer hat Zeile 0 **oben**, deckt sich also bereits mit der
    /// Dokumentkonvention; hier wird bewusst nicht noch einmal gespiegelt.
    private func readPixels(_ data: Data, width: Int, height: Int) throws -> (Int, Int) -> Pixel {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw PipelineError.decodingFailed
        }

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        // Kontext anlegen *und* zeichnen innerhalb des Zugriffs — ein Zeiger auf
        // den Puffer darf den Block nicht überleben.
        let drawn: Bool = buffer.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard drawn else { throw PipelineError.decodingFailed }

        return { x, y in
            let offset = (y * width + x) * 4
            return Pixel(r: buffer[offset], g: buffer[offset + 1], b: buffer[offset + 2], a: buffer[offset + 3])
        }
    }

    private enum PipelineError: Error { case decodingFailed }
}
