import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import SceauCore

/// Schriftauswahl: Liste der Familien und Schnitte, dazu SF Pro.
///
/// SF Pro ist auf macOS nicht als gewöhnliche Schrift installiert, sondern nur
/// als Systemschrift erreichbar — über den Namen angefordert liefert CoreText
/// stillschweigend Times. Diese Tests sichern ab, dass die „SFPro-…"-Namen
/// trotzdem die echte SF Pro in der richtigen Strichstärke ergeben.
@Suite("Schriften — Katalog und SF Pro")
struct FontCatalogTests {

    private func weight(of font: CTFont) -> CGFloat {
        let traits = CTFontCopyTraits(font) as NSDictionary
        return (traits[kCTFontWeightTrait] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
    }

    private func isSFPro(_ font: CTFont) -> Bool {
        let name = CTFontCopyPostScriptName(font) as String
        // Eingebaut heisst sie intern „.SFNS…", heruntergeladen „SFPro-…".
        return name.hasPrefix(".SF") || name.hasPrefix("SFPro")
    }

    @Test("SF Pro wird nicht zu Times, sondern zur echten SF Pro")
    func sfProResolvesToSystemFont() {
        let font = FontCatalog.makeFont(named: "SFPro-Regular", size: 72)
        #expect(isSFPro(font))
        #expect(!(CTFontCopyPostScriptName(font) as String).contains("Times"))
        #expect(CTFontGetSize(font) == 72)
    }

    @Test("SF-Pro-Schnitte haben die passende Strichstärke")
    func sfProWeights() {
        let regular = weight(of: FontCatalog.makeFont(named: "SFPro-Regular", size: 40))
        let bold = weight(of: FontCatalog.makeFont(named: "SFPro-Bold", size: 40))
        let black = weight(of: FontCatalog.makeFont(named: "SFPro-Black", size: 40))
        let thin = weight(of: FontCatalog.makeFont(named: "SFPro-Thin", size: 40))

        #expect(abs(regular) < 0.05)
        #expect(bold > regular + 0.2)
        #expect(black > bold)
        #expect(thin < regular - 0.2)
    }

    @Test("Gewöhnliche Schriften werden über ihren Namen aufgelöst")
    func regularFontByName() {
        let font = FontCatalog.makeFont(named: "Helvetica-Bold", size: 20)
        #expect(CTFontCopyPostScriptName(font) as String == "Helvetica-Bold")
    }

    @Test("Familienliste: SF Pro zuoberst, installierte Schriften, keine versteckten, keine Doppelten")
    func families() {
        let families = FontCatalog.families()
        #expect(families.first == "SF Pro")
        #expect(families.contains("Helvetica"))
        #expect(families.contains("Helvetica Neue"))
        #expect(!families.contains { $0.hasPrefix(".") })
        #expect(Set(families).count == families.count)
    }

    @Test("Schnitte von SF Pro")
    func sfProStyles() {
        let styles = FontCatalog.styles(ofFamily: "SF Pro")
        let names = styles.map(\.postScriptName)
        #expect(names.contains("SFPro-Regular"))
        #expect(names.contains("SFPro-Bold"))
        #expect(styles.first { $0.postScriptName == "SFPro-Bold" }?.name == "Bold")
        // Von dünn nach kräftig sortiert.
        #expect(names.firstIndex(of: "SFPro-Thin")! < names.firstIndex(of: "SFPro-Black")!)
    }

    @Test("Schnitte einer installierten Familie")
    func installedStyles() {
        let styles = FontCatalog.styles(ofFamily: "Helvetica")
        #expect(styles.map(\.postScriptName).contains("Helvetica"))
        #expect(styles.map(\.postScriptName).contains("Helvetica-Bold"))
        #expect(styles.allSatisfy { !$0.name.isEmpty })
    }

    @Test("Familie zu einem gespeicherten Schriftnamen")
    func familyOfName() {
        #expect(FontCatalog.family(ofFontNamed: "SFPro-Semibold") == "SF Pro")
        #expect(FontCatalog.family(ofFontNamed: "Helvetica-Bold") == "Helvetica")
        #expect(FontCatalog.family(ofFontNamed: "GibtEsNicht-Regular") == nil)
    }

    @Test("Text in SF Pro wird mit SF Pro gesetzt, nicht mit der Ersatzschrift")
    func textToPathUsesSFPro() {
        // Ohne Sonderbehandlung setzt CoreText „SFPro-Bold" stillschweigend
        // in Helvetica — gleiche Laufweite wie Helvetica wäre also der Fehler.
        let spec = TextSpec(string: "Sceau Logo", fontName: "SFPro-Bold", fontSize: 100)
        let helvetica = TextSpec(string: "Sceau Logo", fontName: "Helvetica", fontSize: 100)

        // Erwartete Laufweite: Summe der Glyphenbreiten in der echten SF Pro
        // Bold (TextToPath setzt ohne Unterschneidung, also genauso).
        let sfFont = FontCatalog.makeFont(named: "SFPro-Bold", size: 100)
        let characters = Array("Sceau Logo".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        #expect(CTFontGetGlyphsForCharacters(sfFont, characters, &glyphs, characters.count))
        let expected = CGFloat(CTFontGetAdvancesForGlyphs(sfFont, .horizontal, glyphs, nil, glyphs.count))

        #expect(abs(TextToPath.advance(for: spec) - expected) < 0.001)
        #expect(TextToPath.path(for: spec) != TextToPath.path(for: helvetica))
        #expect(!TextToPath.path(for: spec).subpaths.isEmpty)
    }

    @Test("Familienwechsel behält den Schnitt: Bold bleibt Bold")
    func switchFamilyKeepsStyle() {
        #expect(FontCatalog.fontName(inFamily: "SF Pro", closestTo: "Helvetica-Bold") == "SFPro-Bold")
    }

    @Test("Familienwechsel ohne gleichen Schnitt nimmt die nächstliegende Strichstärke")
    func switchFamilyNearestWeight() {
        // Semibold (0,3) liegt näher an Helvetica Bold (0,4) als an Regular (0).
        #expect(FontCatalog.fontName(inFamily: "Helvetica", closestTo: "SFPro-Semibold") == "Helvetica-Bold")
        #expect(FontCatalog.fontName(inFamily: "Helvetica", closestTo: "SFPro-Regular") == "Helvetica")
    }

    @Test("Familienwechsel von einer fehlenden Schrift nimmt den normalen Schnitt")
    func switchFromMissingFont() {
        #expect(FontCatalog.fontName(inFamily: "Helvetica", closestTo: "GibtEsNicht-Regular") == "Helvetica")
    }

    @Test("Unbekannte Familie ergibt keinen Namen")
    func unknownFamily() {
        #expect(FontCatalog.fontName(inFamily: "Gibt Es Nicht", closestTo: "Helvetica") == nil)
    }
}
