import CoreGraphics
import CoreText
import Foundation

/// Ein Schnitt innerhalb einer Schriftfamilie, z. B. „Bold".
public struct FontStyle: Equatable, Sendable, Identifiable {
    public var id: String { postScriptName }
    /// Anzeigename des Schnitts.
    public let name: String
    /// Der Name, der in ``TextSpec/fontName`` gespeichert wird.
    public let postScriptName: String
    /// Strichstärke auf der Skala von `kCTFontWeightTrait` (0 = normal).
    public let weight: CGFloat
    public let isItalic: Bool
}

/// Schriftauswahl für Textebenen — und die einzige Stelle, an der ein
/// gespeicherter Schriftname zu einer echten Schrift wird.
///
/// ## SF Pro
/// Apples SF Pro ist auf macOS nicht als gewöhnliche Schrift installiert,
/// sondern nur als Systemschrift erreichbar. Über ihren Namen angefordert
/// liefert CoreText stillschweigend Times. Gespeichert wird SF Pro deshalb
/// unter den Namen der herunterladbaren Fassung (`SFPro-Bold` usw.): Ist
/// diese installiert, wird sie verwendet, sonst die eingebaute Systemschrift
/// in der entsprechenden Strichstärke. Beides ergibt dieselben Formen.
public enum FontCatalog {

    public static let sfProFamily = "SF Pro"

    private static let sfProPrefix = "SFPro-"

    /// Schnitte von SF Pro mit ihrer Strichstärke (Skala von
    /// `kCTFontWeightTrait`, dieselben Werte wie `NSFont.Weight`), von dünn
    /// nach kräftig.
    private static let sfProWeights: [(name: String, weight: CGFloat)] = [
        ("Ultralight", -0.8),
        ("Thin", -0.6),
        ("Light", -0.4),
        ("Regular", 0),
        ("Medium", 0.23),
        ("Semibold", 0.3),
        ("Bold", 0.4),
        ("Heavy", 0.56),
        ("Black", 0.62)
    ]

    // MARK: - Auflösen

    /// Die Schrift zu einem gespeicherten Namen.
    public static func makeFont(named name: String, size: CGFloat) -> CTFont {
        let named = CTFontCreateWithName(name as CFString, size, nil)
        guard let weight = sfProWeight(forName: name),
              CTFontCopyPostScriptName(named) as String != name
        else { return named }
        return systemFont(weight: weight, size: size)
    }

    private static func sfProWeight(forName name: String) -> CGFloat? {
        guard name.hasPrefix(sfProPrefix) else { return nil }
        let style = name.dropFirst(sfProPrefix.count)
        return sfProWeights.first { $0.name == style }?.weight
    }

    /// Die Systemschrift über die dafür vorgesehene Schnittstelle — nie über
    /// ihren internen Namen („.SFNS…"), den CoreText ablehnt.
    private static func systemFont(weight: CGFloat, size: CGFloat) -> CTFont {
        guard let base = CTFontCreateUIFontForLanguage(.system, size, nil) else {
            return CTFontCreateWithName("HelveticaNeue" as CFString, size, nil)
        }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base),
            [kCTFontTraitsAttribute: [kCTFontWeightTrait: weight]] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    // MARK: - Auswahl

    /// Alle wählbaren Familien: SF Pro zuoberst, dann die installierten
    /// Schriften alphabetisch. Versteckte Systemschriften („.…") fehlen.
    public static func families() -> [String] {
        let installed = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        let visible = Set(installed.filter { !$0.hasPrefix(".") && $0 != sfProFamily })
        return [sfProFamily] + visible.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Die Schnitte einer Familie, von dünn nach kräftig, aufrecht vor kursiv.
    public static func styles(ofFamily family: String) -> [FontStyle] {
        if family == sfProFamily {
            return sfProWeights.map {
                FontStyle(name: $0.name, postScriptName: sfProPrefix + $0.name, weight: $0.weight, isItalic: false)
            }
        }

        let query = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
        let matches = (CTFontDescriptorCreateMatchingFontDescriptors(query, nil) as? [CTFontDescriptor]) ?? []

        var seen = Set<String>()
        let styles: [FontStyle] = matches.compactMap { descriptor in
            guard let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
                  !postScriptName.hasPrefix("."),
                  seen.insert(postScriptName).inserted
            else { return nil }

            let styleName = (CTFontDescriptorCopyLocalizedAttribute(descriptor, kCTFontStyleNameAttribute, nil) as? String)
                ?? (CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String)
                ?? postScriptName
            let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any] ?? [:]
            let weight = (traits[kCTFontWeightTrait] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
            let symbolic = (traits[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
            let italic = symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0
            return FontStyle(name: styleName, postScriptName: postScriptName, weight: weight, isItalic: italic)
        }

        return styles.sorted { a, b in
            if a.weight != b.weight { return a.weight < b.weight }
            if a.isItalic != b.isItalic { return !a.isItalic }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Der Schnitt in `family`, der `currentName` am nächsten kommt — für den
    /// Wechsel der Familie: Bold bleibt Bold, Kursiv bleibt kursiv, sonst die
    /// nächstliegende Strichstärke. Eine fehlende Schrift zählt als normal.
    public static func fontName(inFamily family: String, closestTo currentName: String) -> String? {
        let (weight, italic) = weightAndItalic(ofFontNamed: currentName)
        return styles(ofFamily: family).min { a, b in
            let da = abs(a.weight - weight), db = abs(b.weight - weight)
            if (a.isItalic == italic) != (b.isItalic == italic) { return a.isItalic == italic }
            return da < db
        }?.postScriptName
    }

    private static func weightAndItalic(ofFontNamed name: String) -> (CGFloat, Bool) {
        if let weight = sfProWeight(forName: name) { return (weight, false) }
        guard family(ofFontNamed: name) != nil else { return (0, false) }
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        let traits = CTFontCopyTraits(font) as? [CFString: Any] ?? [:]
        let weight = (traits[kCTFontWeightTrait] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
        return (weight, CTFontGetSymbolicTraits(font).contains(.traitItalic))
    }

    /// Die Familie zu einem gespeicherten Schriftnamen, oder `nil`, wenn die
    /// Schrift nicht installiert ist.
    public static func family(ofFontNamed name: String) -> String? {
        if sfProWeight(forName: name) != nil { return sfProFamily }
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        guard CTFontCopyPostScriptName(font) as String == name else { return nil }
        return CTFontCopyFamilyName(font) as String
    }
}
