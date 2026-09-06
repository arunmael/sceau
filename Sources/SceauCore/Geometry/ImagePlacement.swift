import CoreGraphics

/// Berechnet den Dokumentrahmen für ein neu eingesetztes Bild — gemeinsame
/// Grundlage für "Bild einfügen …" (zentriert auf der Zeichenfläche) und das
/// Ablegen einer Bilddatei per Drag & Drop (zentriert auf dem Ablagepunkt).
public enum ImagePlacement {

    /// - Parameters:
    ///   - pixelSize: Grösse des Bildes in Pixeln.
    ///   - center: Punkt in Dokumentkoordinaten, um den das Bild zentriert wird.
    ///   - maxDimension: Längste erlaubte Kantenlänge in Dokumentpunkten — bei
    ///     grösseren Bildern (z. B. einem 4000px-Foto) wird proportional
    ///     herunterskaliert, damit es nicht weit über die Zeichenfläche hinausragt.
    public static func frame(forPixelSize pixelSize: CGSize, centeredAt center: CGPoint, maxDimension: CGFloat) -> CGRect {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return .zero }

        let longestSide = max(pixelSize.width, pixelSize.height)
        let scale = longestSide > maxDimension && maxDimension > 0 ? maxDimension / longestSide : 1
        let size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)

        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
