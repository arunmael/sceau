import CoreGraphics

/// Eine Farbe im sRGB-Raum mit Alpha, Komponenten jeweils 0…1.
///
/// Bewusst eine eigene, plattformunabhängige Wertsemantik statt `NSColor` —
/// damit bleibt das Dokumentmodell serialisierbar, `Sendable` und ohne
/// AppKit-Abhängigkeit testbar.
public struct RGBAColor: Equatable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clamped01
        self.green = green.clamped01
        self.blue = blue.clamped01
        self.alpha = alpha.clamped01
    }

    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)

    private enum CodingKeys: String, CodingKey { case red, green, blue, alpha }

    /// Von Hand geschrieben statt synthetisiert, damit auch aus einer
    /// beschädigten oder von Hand geänderten Dokumentdatei dekodierte
    /// Komponenten durch dieselbe Klemmung laufen wie der normale
    /// Konstruktor — sonst könnten ausser Reichweite liegende oder nicht
    /// endliche Werte bis zu einer späteren `Int(...)`-Umwandlung (Hex-Anzeige,
    /// Prozentanzeige) durchrutschen und dort abstürzen.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue),
            alpha: try container.decode(Double.self, forKey: .alpha)
        )
    }
}

private extension Double {
    /// Klemmt auf 0…1 und bildet dabei auch nicht endliche Werte auf einen
    /// gültigen Rand ab, statt sie (undefiniert) durch den Vergleich laufen
    /// zu lassen: NaN kennt keine sinnvolle Seite und wird auf 0 abgebildet,
    /// +/-Infinity auf den jeweils nächstliegenden Rand.
    var clamped01: Double {
        guard isFinite else {
            if isNaN { return 0 }
            return self > 0 ? 1 : 0
        }
        return Swift.min(1, Swift.max(0, self))
    }
}

/// Ein Farbstopp eines Verlaufs.
public struct GradientStop: Equatable, Sendable, Codable {
    public var color: RGBAColor
    /// Position entlang der Verlaufsachse, 0…1.
    public var location: CGFloat

    public init(color: RGBAColor, location: CGFloat) {
        self.color = color
        self.location = location.clampedUnitOrZero
    }

    private enum CodingKeys: String, CodingKey { case color, location }

    /// Siehe ``RGBAColor/init(from:)`` — dieselbe Absicherung für den
    /// zweiten Wert, der unmittelbar in eine Prozentanzeige (`Int(...)`)
    /// einfliesst.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            color: try container.decode(RGBAColor.self, forKey: .color),
            location: try container.decode(CGFloat.self, forKey: .location)
        )
    }
}

private extension CGFloat {
    var clampedUnitOrZero: CGFloat {
        guard isFinite else { return isNaN ? 0 : (self > 0 ? 1 : 0) }
        return Swift.min(1, Swift.max(0, self))
    }
}

/// Ein linearer oder radialer Verlauf mit 2–3 Farbstopps.
///
/// Start- und Endpunkt sind **normalisiert** auf den Hüllrahmen der Form
/// (0,0 = links oben, 1,1 = rechts unten). Dadurch bleibt der Verlauf beim
/// Skalieren der Form korrekt, ohne mitgeführt werden zu müssen.
public struct Gradient: Equatable, Sendable, Codable {
    public var stops: [GradientStop]
    public var start: CGPoint
    public var end: CGPoint

    public init(stops: [GradientStop], start: CGPoint, end: CGPoint) {
        self.stops = stops
        self.start = start
        self.end = end
    }
}

/// Womit eine Fläche oder eine Kontur gefüllt wird.
///
/// Mesh-Verläufe und Musterfüllungen sind laut Entwicklungsplan bewusst nicht
/// Teil des Funktionsumfangs.
public enum Paint: Equatable, Sendable, Codable {
    case none
    case solid(RGBAColor)
    case linearGradient(Gradient)
    case radialGradient(Gradient)
}

/// Art der Konturenden.
public enum StrokeCap: String, Equatable, Sendable, Codable, CaseIterable {
    case butt, round, square
}

/// Art der Konturecken.
public enum StrokeJoin: String, Equatable, Sendable, Codable, CaseIterable {
    case miter, round, bevel
}

/// Die Kontur einer Form.
public struct Stroke: Equatable, Sendable, Codable {
    public var paint: Paint
    public var width: CGFloat
    public var cap: StrokeCap
    public var join: StrokeJoin
    /// Strichmuster; leer bedeutet durchgezogen.
    public var dash: [CGFloat]

    public init(
        paint: Paint = .solid(.black),
        width: CGFloat = 1,
        cap: StrokeCap = .butt,
        join: StrokeJoin = .miter,
        dash: [CGFloat] = []
    ) {
        self.paint = paint
        self.width = width
        self.cap = cap
        self.join = join
        self.dash = dash
    }

    /// `true`, wenn die Kontur tatsächlich sichtbar zeichnet.
    public var isVisible: Bool {
        width > 0 && paint != .none
    }
}

/// Regel, nach der bei mehreren Teilpfaden entschieden wird, was Fläche und was
/// Loch ist.
public enum FillRule: String, Equatable, Sendable, Codable, CaseIterable {
    case nonZero
    case evenOdd
}

/// Das vollständige Erscheinungsbild eines Knotens.
public struct Style: Equatable, Sendable, Codable {
    public var fill: Paint
    public var stroke: Stroke?
    public var fillRule: FillRule
    /// Deckkraft des gesamten Knotens, 0…1 — wirkt zusätzlich zum Alpha der Farben.
    public var opacity: CGFloat

    public init(
        fill: Paint = .solid(RGBAColor(red: 0.35, green: 0.42, blue: 0.95)),
        stroke: Stroke? = nil,
        fillRule: FillRule = .nonZero,
        opacity: CGFloat = 1
    ) {
        self.fill = fill
        self.stroke = stroke
        self.fillRule = fillRule
        self.opacity = opacity
    }
}
