import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SceauCore

/// Prüft die Darstellung anhand der tatsächlichen Bildpunkte.
///
/// Verläufe, Konturen, Füllregel und Deckkraft waren bisher nur mittelbar
/// abgedeckt: Dass ein PNG entsteht, sagt nichts darüber, ob es richtig
/// aussieht. Weil Export-Korrektheit laut Entwicklungsplan Vorrang hat, wird
/// hier gegen einen echten Decoder gemessen statt gegen die eigene Rechnung.
@Suite("Darstellungstreue — gegen die Bildpunkte geprüft")
struct RenderingFidelityTests {

    private struct Pixel: CustomStringConvertible {
        let r, g, b, a: UInt8
        var description: String { "rgba(\(r),\(g),\(b),\(a))" }
    }

    private enum FehlerBeimLesen: Error { case decodingFailed }

    /// Liest ein PNG zurück. Zeile 0 liegt oben, deckt sich also mit der
    /// Dokumentkonvention.
    private func pixels(_ data: Data, size: Int) throws -> (Int, Int) -> Pixel {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw FehlerBeimLesen.decodingFailed }

        var buffer = [UInt8](repeating: 0, count: size * size * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ok: Bool = buffer.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
            return true
        }
        guard ok else { throw FehlerBeimLesen.decodingFailed }

        return { x, y in
            let offset = (y * size + x) * 4
            return Pixel(r: buffer[offset], g: buffer[offset + 1],
                         b: buffer[offset + 2], a: buffer[offset + 3])
        }
    }

    private func render(_ nodes: [Node], size: Int = 100) throws -> (Int, Int) -> Pixel {
        var document = Document(artboard: Artboard(size: CGSize(width: 100, height: 100)))
        document.nodes = nodes
        let data = try RasterExporter.pngData(document, pixelWidth: size, pixelHeight: size)
        return try pixels(data, size: size)
    }

    private func fullRect(style: Style) -> Node {
        Node(
            name: "Fläche",
            style: style,
            content: .shape(.rectangle(frame: CGRect(x: 0, y: 0, width: 100, height: 100), cornerRadius: 0))
        )
    }

    /// Baut eine winzige, einfarbige PNG-Kachel — genug, um zu prüfen, dass
    /// eine Musterfüllung tatsächlich das Bild und nicht Transparenz oder die
    /// Grundfarbe zeigt.
    private func solidColorPNG(red: UInt8, green: UInt8, blue: UInt8) -> Data {
        var pixels: [UInt8] = []
        for _ in 0..<16 { pixels.append(contentsOf: [red, green, blue, 255]) }
        let space = CGColorSpaceCreateDeviceRGB()
        let data = pixels.withUnsafeMutableBytes { bytes -> Data in
            let context = CGContext(
                data: bytes.baseAddress, width: 4, height: 4,
                bitsPerComponent: 8, bytesPerRow: 16, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )!
            let image = context.makeImage()!
            let mutableData = NSMutableData()
            let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            return mutableData as Data
        }
        return data
    }

    @Test("Eine Musterfüllung zeigt die Bildkachel, nicht Transparenz oder eine Grundfarbe")
    func patternFillRendersImage() throws {
        let tile = solidColorPNG(red: 20, green: 200, blue: 40)
        var style = Style()
        style.fill = .pattern(PatternFill(imageData: tile, tileSize: CGSize(width: 10, height: 10)))

        let p = try render([fullRect(style: style)])
        let mitte = p(50, 50)

        #expect(mitte.g > 150 && mitte.r < 100 && mitte.a > 200, "erwartet grüne Kachel, war \(mitte)")
    }

    @Test("Eine gedrehte Musterfüllung mit winzigen Kacheln auf grosser Fläche friert nicht ein")
    func patternFillWithTinyTilesStaysBounded() throws {
        let tile = solidColorPNG(red: 255, green: 0, blue: 0)
        var style = Style()
        // Bewusst absurd kleine Kachel auf grosser Fläche plus Drehung — genau
        // der Fall, den der Kachel-Deckel in DocumentRenderer abfangen muss.
        style.fill = .pattern(PatternFill(imageData: tile, tileSize: CGSize(width: 0.05, height: 0.05), rotation: 0.4))

        let start = Date()
        let p = try render([fullRect(style: style)], size: 400)
        let seconds = Date().timeIntervalSince(start)

        #expect(p(200, 200).r > 0)
        #expect(seconds < 5, "Musterfüllung mit winziger Kachelgrösse dauerte \(seconds) s — Deckel greift nicht?")
    }

    @Test("Ein Schlagschatten färbt einen Punkt ausserhalb der Form unten rechts vom Objekt, nicht oben links")
    func shadowAppearsBelowAndRightOfShape() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 100, height: 100), background: .white))
        var style = Style(fill: .solid(.black))
        style.shadow = Shadow(color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1), offset: CGSize(width: 15, height: 15), blurRadius: 0)
        document.nodes = [
            Node(
                name: "Quadrat",
                style: style,
                content: .shape(.rectangle(frame: CGRect(x: 20, y: 20, width: 30, height: 30), cornerRadius: 0))
            )
        ]

        let data = try RasterExporter.pngData(document, pixelWidth: 100, pixelHeight: 100)
        let p = try pixels(data, size: 100)

        // Direkt unter-rechts der Form (ausserhalb ihrer eigenen Fläche, die
        // bei x,y 20...50 liegt) sollte der ungeblurrte, um (15,15) versetzte
        // rote Schatten liegen. Oben links der Form (ausserhalb) bleibt weiss.
        let untenRechtsVomSchatten = p(55, 55)
        let obenLinksAusserhalb = p(10, 10)

        #expect(untenRechtsVomSchatten.r > 200 && untenRechtsVomSchatten.g < 60, "erwartet roten Schatten bei (55,55), war \(untenRechtsVomSchatten)")
        #expect(obenLinksAusserhalb.r > 240 && obenLinksAusserhalb.g > 240 && obenLinksAusserhalb.b > 240, "erwartet weiss bei (10,10), war \(obenLinksAusserhalb)")
    }

    @Test("Ein linearer Verlauf färbt die Ecken unterschiedlich")
    func linearGradientRuns() throws {
        var style = Style()
        style.fill = .linearGradient(Gradient(
            stops: [
                GradientStop(color: RGBAColor(red: 1, green: 0, blue: 0), location: 0),
                GradientStop(color: RGBAColor(red: 0, green: 0, blue: 1), location: 1)
            ],
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 1, y: 1)
        ))

        let p = try render([fullRect(style: style)])
        let obenLinks = p(5, 5)
        let untenRechts = p(94, 94)

        #expect(obenLinks.r > 200 && obenLinks.b < 60, "oben links erwartet rot, war \(obenLinks)")
        #expect(untenRechts.b > 200 && untenRechts.r < 60, "unten rechts erwartet blau, war \(untenRechts)")
    }

    @Test("Ein radialer Verlauf unterscheidet Mitte und Rand")
    func radialGradientRuns() throws {
        var style = Style()
        style.fill = .radialGradient(Gradient(
            stops: [
                GradientStop(color: RGBAColor(red: 1, green: 1, blue: 1), location: 0),
                GradientStop(color: RGBAColor(red: 0, green: 0, blue: 0), location: 1)
            ],
            start: CGPoint(x: 0.5, y: 0.5),
            end: CGPoint(x: 1, y: 1)
        ))

        let p = try render([fullRect(style: style)])
        #expect(p(50, 50).r > p(5, 50).r, "die Mitte muss heller sein als der Rand")
    }

    @Test("Eine Kontur zeichnet am Rand, nicht in der Fläche")
    func strokeDrawsOnTheEdge() throws {
        var style = Style()
        style.fill = .none
        style.stroke = Stroke(paint: .solid(.black), width: 10)

        let node = Node(
            name: "Umriss",
            style: style,
            content: .shape(.rectangle(frame: CGRect(x: 20, y: 20, width: 60, height: 60), cornerRadius: 0))
        )

        let p = try render([node])
        let aufDerKante = p(50, 20)
        let inDerMitte = p(50, 50)

        #expect(aufDerKante.a > 200, "die Kante muss gezeichnet sein, war \(aufDerKante)")
        #expect(inDerMitte.a == 0, "ohne Füllung muss die Fläche durchsichtig bleiben, war \(inDerMitte)")
    }

    @Test("Die Füllregel evenOdd erzeugt ein Loch, nonZero nicht")
    func fillRuleDecidesTheHole() throws {
        // Zwei ineinanderliegende Rechtecke mit **gleichem** Umlaufsinn: Erst
        // die Füllregel entscheidet, ob das innere ein Loch wird.
        let aussen = Subpath(closedPolygon: [
            CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 10),
            CGPoint(x: 90, y: 90), CGPoint(x: 10, y: 90)
        ])
        let innen = Subpath(closedPolygon: [
            CGPoint(x: 30, y: 30), CGPoint(x: 70, y: 30),
            CGPoint(x: 70, y: 70), CGPoint(x: 30, y: 70)
        ])
        let path = VectorPath(subpaths: [aussen, innen])

        var evenOdd = Style()
        evenOdd.fill = .solid(.black)
        evenOdd.fillRule = .evenOdd

        var nonZero = Style()
        nonZero.fill = .solid(.black)
        nonZero.fillRule = .nonZero

        let mitLoch = try render([Node(name: "Loch", style: evenOdd, content: .path(path))])
        let ohneLoch = try render([Node(name: "Voll", style: nonZero, content: .path(path))])

        #expect(mitLoch(50, 50).a == 0, "evenOdd muss ein Loch lassen, war \(mitLoch(50, 50))")
        #expect(mitLoch(20, 50).a > 200, "der Ring dazwischen muss gefüllt sein")
        #expect(ohneLoch(50, 50).a > 200, "nonZero füllt bei gleichem Umlaufsinn durch")
    }

    @Test("Deckkraft schlägt auf den Alphawert durch")
    func opacityReachesThePixels() throws {
        var style = Style()
        style.fill = .solid(.black)
        style.opacity = 0.5

        let p = try render([fullRect(style: style)])
        let mitte = p(50, 50)
        #expect(mitte.a > 110 && mitte.a < 145, "erwartet etwa halbe Deckkraft, war \(mitte)")
    }

    @Test("Unsichtbare Knoten hinterlassen keine Spur")
    func invisibleNodesLeaveNothing() throws {
        var style = Style()
        style.fill = .solid(.black)
        var node = fullRect(style: style)
        node.isVisible = false

        let p = try render([node])
        #expect(p(50, 50).a == 0)
    }
}
