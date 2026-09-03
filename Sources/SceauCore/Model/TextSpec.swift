import CoreGraphics

/// Eine Textebene.
///
/// Bewusst nur die Angaben, die Logo- und Wortmarken-Arbeit braucht: Schrift,
/// Grösse, Zeichen- und Wortabstand. Kein Text-auf-Pfad und keine
/// Absatzformatierung — das wäre Layout-Funktionalität.
public struct TextSpec: Equatable, Sendable, Codable {
    public var string: String
    /// PostScript-Name der Schrift, z. B. `"Helvetica-Bold"`.
    public var fontName: String
    public var fontSize: CGFloat
    /// Zusätzlicher Zeichenabstand in Punkt (Basis-Kerning).
    public var tracking: CGFloat
    /// Zusätzlicher Wortabstand in Punkt.
    public var wordSpacing: CGFloat
    /// Startpunkt der Grundlinie des ersten Zeichens.
    public var origin: CGPoint

    public init(
        string: String,
        fontName: String = "HelveticaNeue-Bold",
        fontSize: CGFloat = 72,
        tracking: CGFloat = 0,
        wordSpacing: CGFloat = 0,
        origin: CGPoint = .zero
    ) {
        self.string = string
        self.fontName = fontName
        self.fontSize = fontSize
        self.tracking = tracking
        self.wordSpacing = wordSpacing
        self.origin = origin
    }
}
