import CoreGraphics
import Foundation
import ImageIO

/// Lädt eine Bilddatei und bettet sie als neuen Bildknoten ins Dokument ein —
/// gemeinsame Grundlage für „Bild einfügen …" (zentriert auf der
/// Zeichenfläche) und das Ablegen einer Bilddatei per Drag & Drop auf die
/// Zeichenfläche (zentriert auf dem Ablagepunkt). Die reine Rahmenberechnung
/// dafür steckt in ``ImagePlacement``.
@MainActor
public enum ImageInsertion {

    /// - Parameters:
    ///   - url: Pfad der Bilddatei (PNG/JPEG).
    ///   - center: Punkt in Dokumentkoordinaten, um den das Bild zentriert wird.
    ///   - store: Dokument, in das der neue Bildknoten eingefügt wird — wird
    ///     dabei ausgewählt.
    ///   - maxDimension: siehe ``ImagePlacement/frame(forPixelSize:centeredAt:maxDimension:)``.
    /// - Returns: `false`, wenn sich `url` nicht als Bild lesen liess — das
    ///   Dokument bleibt dann unverändert.
    @discardableResult
    public static func insert(
        from url: URL,
        centeredAt center: CGPoint,
        into store: DocumentStore,
        maxDimension: CGFloat
    ) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return false }

        let frame = ImagePlacement.frame(
            forPixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            centeredAt: center,
            maxDimension: maxDimension
        )

        let node = Node(
            name: url.deletingPathExtension().lastPathComponent,
            content: .image(ImageSpec(data: data, frame: frame))
        )
        store.apply("Bild einfügen") { $0.appendOnTop(node) }
        store.selection = [node.id]
        return true
    }
}
