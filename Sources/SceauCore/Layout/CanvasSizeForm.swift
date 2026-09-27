import CoreGraphics

/// Zustand des Dialogs „Leinwandgrösse ändern".
///
/// Hält Vorlage und Eingabefelder stimmig: Eine Vorlage wählen setzt die
/// Masse, Masse von Hand ändern wählt die passende Vorlage oder „Eigene
/// Grösse" (`preset == nil`). Die Ebenen selbst fasst der Dialog nicht an —
/// da der Ursprung der Zeichenfläche links oben liegt, behalten sie beim
/// Ändern der Grösse von allein ihre Lage relativ zu dieser Ecke.
public struct CanvasSizeForm: Equatable, Sendable {

    /// Grösste erlaubte Seitenlänge in Punkten — dieselbe Grenze, die der
    /// Rasterexport ohnehin je Seite einhält.
    public static let maximumLength = 16384

    private var storedWidth: Int
    private var storedHeight: Int

    /// Gewählte Vorlage, `nil` für „Eigene Grösse".
    public private(set) var preset: ArtboardPreset?

    public init(size: CGSize) {
        storedWidth = Self.rounded(size.width)
        storedHeight = Self.rounded(size.height)
        preset = nil
        preset = firstMatchingPreset()
    }

    public var width: Int {
        get { storedWidth }
        set { storedWidth = newValue; syncPreset() }
    }

    public var height: Int {
        get { storedHeight }
        set { storedHeight = newValue; syncPreset() }
    }

    /// Übernimmt die Masse einer Vorlage; `nil` wechselt auf „Eigene Grösse"
    /// und lässt die Masse stehen.
    public mutating func choose(_ preset: ArtboardPreset?) {
        self.preset = preset
        guard let preset else { return }
        storedWidth = Self.rounded(preset.size.width)
        storedHeight = Self.rounded(preset.size.height)
    }

    /// Die anzuwendende Grösse, oder `nil`, solange die Eingabe ungültig ist.
    public var size: CGSize? {
        let range = 1...Self.maximumLength
        guard range.contains(storedWidth), range.contains(storedHeight) else { return nil }
        return CGSize(width: storedWidth, height: storedHeight)
    }

    // MARK: - Intern

    /// Eine ausdrücklich gewählte Vorlage bleibt, solange sie passt — sonst
    /// sprängen gleich grosse Vorlagen (Profilbild/Quadrat 512) beim Tippen
    /// auf die jeweils erste.
    private mutating func syncPreset() {
        if let preset, matches(preset) { return }
        preset = firstMatchingPreset()
    }

    private func firstMatchingPreset() -> ArtboardPreset? {
        ArtboardPreset.all.first(where: matches)
    }

    private func matches(_ preset: ArtboardPreset) -> Bool {
        Self.rounded(preset.size.width) == storedWidth && Self.rounded(preset.size.height) == storedHeight
    }

    /// Begrenzt vor der Umwandlung: `Int(_:)` bricht bei Werten ausserhalb
    /// seines Bereichs das Programm ab, und eine beschädigte Datei kann
    /// beliebige Grössen enthalten. Alles jenseits der Grenze ist ohnehin
    /// ungültig, der genaue Wert spielt dann keine Rolle mehr.
    private static func rounded(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 0 }
        let limit = CGFloat(maximumLength + 1)
        return Int(min(max(value.rounded(), -limit), limit))
    }
}
