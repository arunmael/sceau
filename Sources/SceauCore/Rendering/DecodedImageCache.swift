import CoreGraphics
import Foundation
import ImageIO

/// Wählt die Auflösung, in der ein Bild für die Anzeige dekodiert wird.
///
/// Ein Foto mit 24 Megapixeln ergibt dekodiert rund 96 MB — auf der
/// Zeichenfläche ist es aber oft nur ein paar hundert Punkte gross. Dekodiert
/// wird deshalb nur so viel, wie auf dem Bildschirm tatsächlich ankommt.
/// Der Export bleibt davon unberührt und arbeitet immer mit dem Original.
public enum DisplayImageResolution {

    /// Kleinste Stufe — darunter lohnt sich keine eigene Dekodierung mehr.
    public static let minimumPixelSize = 64

    /// Längste Bildseite in Pixeln, auf die verkleinert dekodiert wird, oder
    /// `nil` für die volle Auflösung.
    ///
    /// Gerundet wird auf die nächste Zweierpotenz über dem Bedarf: Beim
    /// Zoomen wird so nur an wenigen Schwellen neu dekodiert statt bei jedem
    /// Schritt, und das Bild ist nie unschärfer als nötig.
    ///
    /// - Parameters:
    ///   - imagePixelSize: Grösse des Originalbilds in Pixeln.
    ///   - displaySize: Grösse, in der das Bild auf dem Bildschirm erscheint,
    ///     in Bildschirmpixeln (also inklusive Zoom und Retina-Faktor).
    public static func maxPixelSize(imagePixelSize: CGSize, displaySize: CGSize) -> Int? {
        let longestSide = max(imagePixelSize.width, imagePixelSize.height)
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return nil }

        // Bei verzerrter Einpassung entscheidet die stärker vergrösserte
        // Achse — sonst würde sie unscharf.
        let scale = max(
            max(0, displaySize.width) / imagePixelSize.width,
            max(0, displaySize.height) / imagePixelSize.height
        )
        guard scale < 1 else { return nil }

        let needed = Int((longestSide * scale).rounded(.up))
        var bucket = minimumPixelSize
        while bucket < needed { bucket *= 2 }

        return CGFloat(bucket) >= longestSide ? nil : bucket
    }
}

/// Hält dekodierte Bilder für die Zeichenfläche vor.
///
/// Die Zeichenfläche baut ihren Ebenenbaum bei jeder Änderung komplett neu
/// (siehe `CanvasRenderer`). Ohne diesen Cache würde dabei jedes Foto bei
/// jedem Mausschritt erneut dekodiert — auf dem Main Thread, also auf einem
/// einzigen Kern, was sich als Ruckeln zeigt, obwohl die Gesamtauslastung
/// niedrig aussieht.
///
/// Einträge, die über einen Neubau hinweg nicht mehr abgefragt werden (Bild
/// gelöscht, ausgeblendet, ersetzt), räumt ``purgeUnused()`` ab.
@MainActor
public final class DecodedImageCache {

    private struct Entry {
        let pixelSize: CGSize
        var maxPixelSize: Int?
        var image: CGImage
        var used: Bool
    }

    private var entries: [Key: Entry] = [:]

    /// Anzahl tatsächlicher Dekodierungen — für Tests.
    private(set) var decodeCount = 0

    /// Anzahl vorgehaltener Bilder.
    public var count: Int { entries.count }

    public init() {}

    /// Das dekodierte Bild für `data`, passend zur Anzeigegrösse.
    ///
    /// - Parameter displaySize: Grösse in Bildschirmpixeln, siehe
    ///   ``DisplayImageResolution/maxPixelSize(imagePixelSize:displaySize:)``.
    /// - Returns: `nil`, wenn sich `data` nicht als Bild lesen lässt.
    public func image(for data: Data, displaySize: CGSize) -> CGImage? {
        let key = Key(data)

        if var entry = entries[key] {
            let wanted = DisplayImageResolution.maxPixelSize(
                imagePixelSize: entry.pixelSize, displaySize: displaySize
            )
            if wanted != entry.maxPixelSize,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = decode(source, maxPixelSize: wanted) {
                entry.image = image
                entry.maxPixelSize = wanted
            }
            entry.used = true
            entries[key] = entry
            return entry.image
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let pixelSize = Self.pixelSize(of: source)
        else { return nil }

        let wanted = DisplayImageResolution.maxPixelSize(imagePixelSize: pixelSize, displaySize: displaySize)
        guard let image = decode(source, maxPixelSize: wanted) else { return nil }

        entries[key] = Entry(pixelSize: pixelSize, maxPixelSize: wanted, image: image, used: true)
        return image
    }

    /// Entfernt alle Bilder, die seit dem letzten Aufruf nicht abgefragt
    /// wurden. Gedacht für das Ende jedes Neubaus der Zeichenfläche.
    public func purgeUnused() {
        entries = entries.filter { $0.value.used }
        for key in entries.keys { entries[key]?.used = false }
    }

    // MARK: - Dekodieren

    /// Dekodiert sofort statt beim ersten Zeichnen — sonst würde Core
    /// Animation die Pixel womöglich bei jedem Neubau erneut auspacken.
    ///
    /// Die EXIF-Ausrichtung wird bewusst nicht angewandt: Der Export
    /// (`DocumentRenderer`) zeigt das Bild ebenfalls ungedreht, und
    /// Zeichenfläche und Export sollen übereinstimmen.
    private func decode(_ source: CGImageSource, maxPixelSize: Int?) -> CGImage? {
        decodeCount += 1
        guard let maxPixelSize else {
            return CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }
        // `FromImageAlways`: nie das eingebettete EXIF-Vorschaubild nehmen —
        // das ist oft winzig oder anders beschnitten.
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    /// Liest die Pixelgrösse aus den Kopfdaten, ohne das Bild zu dekodieren.
    private static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    // MARK: - Schlüssel

    /// Schlüssel über den Inhalt der Bilddaten, aber ohne bei jedem Nachschlagen
    /// Megabytes zu hashen.
    ///
    /// Der Hash nimmt nur Länge sowie Anfang und Ende der Daten — das reicht,
    /// um verschiedene Bilder praktisch immer zu trennen. Die Gleichheit prüft
    /// zuerst, ob beide Werte denselben Puffer teilen (der Normalfall: das
    /// Dokument und seine Undo-Stände kopieren `Data` nur per Referenz), und
    /// vergleicht erst sonst den ganzen Inhalt. Damit bleibt der Schlüssel
    /// korrekt, auch bei Hash-Kollisionen.
    private struct Key: Hashable {
        let data: Data

        init(_ data: Data) { self.data = data }

        func hash(into hasher: inout Hasher) {
            hasher.combine(data.count)
            hasher.combine(data.prefix(64))
            hasher.combine(data.suffix(64))
        }

        static func == (lhs: Key, rhs: Key) -> Bool {
            guard lhs.data.count == rhs.data.count else { return false }
            let sameBuffer = lhs.data.withUnsafeBytes { a in
                rhs.data.withUnsafeBytes { b in a.baseAddress == b.baseAddress }
            }
            return sameBuffer || lhs.data == rhs.data
        }
    }
}
