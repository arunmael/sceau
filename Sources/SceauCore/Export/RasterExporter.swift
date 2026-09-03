import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Fehler, die beim Rasterisieren oder PDF-Export auftreten können.
public enum ExportError: Error, Equatable {
    /// Eine angeforderte Pixel- oder Kantenlänge war 0 oder negativ.
    case invalidSize
    /// `CGContext`/`CGImageDestination`/`CGDataConsumer` liess sich nicht anlegen.
    case contextCreationFailed
    /// Die Kodierung (PNG) ist fehlgeschlagen, obwohl der Kontext entstand.
    case encodingFailed
}

/// Rasterisiert ein ``Document`` als PNG, in einer oder mehreren Pixelgrössen.
///
/// Nutzt **ImageIO**, nicht `NSBitmapImageRep` — `SceauCore` darf laut
/// Architektur nicht von AppKit abhängen, damit die Geometrie- und
/// Export-Logik auch ausserhalb der App (z. B. in Tests oder einem
/// Kommandozeilenwerkzeug) ohne UI-Framework läuft.
public enum RasterExporter {

    /// PNG in einer bestimmten Pixelgrösse. Die Zeichenfläche
    /// (`document.artboard.size`) wird auf die Zielgrösse skaliert eingepasst.
    public static func pngData(_ document: Document, pixelWidth: Int, pixelHeight: Int) throws -> Data {
        guard pixelWidth > 0, pixelHeight > 0 else { throw ExportError.invalidSize }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        // premultipliedLast (RGBA) ist die Belegung, die ImageIO beim
        // Schreiben eines PNG mit Alphakanal erwartet.
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ExportError.contextCreationFailed
        }

        let artboardSize = document.artboard.size
        guard artboardSize.width > 0, artboardSize.height > 0 else { throw ExportError.invalidSize }

        let scaleX = CGFloat(pixelWidth) / artboardSize.width
        let scaleY = CGFloat(pixelHeight) / artboardSize.height

        // Einzige Stelle, an der zwischen Dokumentkoordinaten (Ursprung links
        // oben, y nach unten) und `CGContext`-Koordinaten (Ursprung links
        // unten, y nach oben) vermittelt wird: erst auf die volle Höhe
        // verschieben, dann die y-Achse spiegeln. Ohne das stünde jeder
        // Bitmap- und PDF-Export auf dem Kopf.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: scaleX, y: scaleY)

        DocumentRenderer.draw(document, in: context, drawBackground: true)

        guard let image = context.makeImage() else { throw ExportError.encodingFailed }
        return try encodePNG(image)
    }

    /// Mehrere quadratische Grössen in einem Durchgang — für Icon-Sätze.
    /// Ergebnis ist nach Kantenlänge aufsteigend sortiert.
    public static func iconSet(_ document: Document, sizes: [Int]) throws -> [(size: Int, data: Data)] {
        try sizes.sorted().map { size in
            (size: size, data: try pngData(document, pixelWidth: size, pixelHeight: size))
        }
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.contextCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.encodingFailed }
        return data as Data
    }
}

/// Exportiert ein ``Document`` als einseitiges, verlustfreies PDF.
///
/// `CGContext` ist im Kern selbst PDF-fähig — anders als bei SVG braucht es
/// hier keinen eigenen Konverter, nur die richtige Kontext-Einrichtung.
public enum PDFExporter {

    public static func pdfData(_ document: Document) throws -> Data {
        let size = document.artboard.size
        guard size.width > 0, size.height > 0 else { throw ExportError.invalidSize }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw ExportError.contextCreationFailed }

        var mediaBox = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.contextCreationFailed
        }

        context.beginPDFPage(nil)
        // Gleiche Spiegelung wie beim PNG-Export: das PDF-Koordinatensystem
        // hat seinen Ursprung ebenfalls links unten, das Dokumentmodell links
        // oben.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        DocumentRenderer.draw(document, in: context, drawBackground: true)
        context.endPDFPage()
        context.closePDF()

        return data as Data
    }
}
