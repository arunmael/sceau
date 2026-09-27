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
    /// Horizontale Skalierung, 1 = unverzerrt. Streckt oder staucht den Text
    /// vom Startpunkt aus in der Breite — entsteht beim unproportionalen
    /// Ziehen an den Griffen, damit sich Text wie ein Bild verziehen lässt
    /// und trotzdem editierbarer Text bleibt.
    public var horizontalScale: CGFloat

    public init(
        string: String,
        fontName: String = "HelveticaNeue-Bold",
        fontSize: CGFloat = 72,
        tracking: CGFloat = 0,
        wordSpacing: CGFloat = 0,
        origin: CGPoint = .zero,
        horizontalScale: CGFloat = 1
    ) {
        self.string = string
        self.fontName = fontName
        self.fontSize = fontSize
        self.tracking = tracking
        self.wordSpacing = wordSpacing
        self.origin = origin
        self.horizontalScale = horizontalScale
    }

    /// Eigene Dekodierung nur, damit Dateien aus der Zeit vor
    /// ``horizontalScale`` weiterhin öffnen — dort fehlt der Wert und gilt als 1.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        string = try container.decode(String.self, forKey: .string)
        fontName = try container.decode(String.self, forKey: .fontName)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        tracking = try container.decode(CGFloat.self, forKey: .tracking)
        wordSpacing = try container.decode(CGFloat.self, forKey: .wordSpacing)
        origin = try container.decode(CGPoint.self, forKey: .origin)
        horizontalScale = try container.decodeIfPresent(CGFloat.self, forKey: .horizontalScale) ?? 1
    }
}
