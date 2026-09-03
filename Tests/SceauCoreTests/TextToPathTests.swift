import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("TextToPath — Text zu Konturen")
struct TextToPathTests {

    @Test("Grundlinien-Spiegelung: Oberlängen liegen über der Grundlinie")
    func glyphIsMirroredAboveBaseline() {
        // Das Dokumentmodell zählt y nach unten, CoreText liefert Glyphen mit
        // y nach oben ab der Grundlinie. Ohne Spiegelung stünde das „H" auf
        // dem Kopf und läge unterhalb von origin.y statt darüber.
        let spec = TextSpec(string: "H", fontName: "Helvetica", fontSize: 200, origin: CGPoint(x: 0, y: 100))
        let path = TextToPath.path(for: spec)
        let bounds = path.bounds

        #expect(!bounds.isNull)
        #expect(bounds.maxY <= 100.5, "Unterkante des H muss auf/über der Grundlinie liegen: \(bounds.maxY)")
        #expect(bounds.minY < 100, "Oberkante des H muss über der Grundlinie liegen: \(bounds.minY)")
    }

    @Test("Buchstabe H erzeugt einen nicht leeren Pfad mit mindestens einem geschlossenen Teilpfad")
    func hProducesNonEmptyClosedPath() {
        let spec = TextSpec(string: "H", fontName: "Helvetica", fontSize: 72, origin: .zero)
        let path = TextToPath.path(for: spec)

        #expect(!path.isEmpty)
        let hasClosedSubpath = path.subpaths.contains { $0.isClosed }
        #expect(hasClosedSubpath)
    }

    @Test("Buchstabe O mit Punze erzeugt mindestens zwei Teilpfade")
    func oProducesAtLeastTwoSubpaths() {
        let spec = TextSpec(string: "O", fontName: "Helvetica", fontSize: 72, origin: .zero)
        let path = TextToPath.path(for: spec)

        #expect(path.subpaths.count >= 2)
    }

    @Test("Leerer Text ergibt einen leeren Pfad")
    func emptyStringProducesEmptyPath() {
        let spec = TextSpec(string: "", fontName: "Helvetica", fontSize: 72, origin: .zero)
        let path = TextToPath.path(for: spec)

        #expect(path.isEmpty)
    }

    @Test("Nicht existierende Schrift stürzt nicht ab und liefert eine Ersatzschrift")
    func missingFontFallsBackWithoutCrashing() {
        let spec = TextSpec(string: "Abc", fontName: "DieseSchriftGibtEsNicht-XYZ", fontSize: 72, origin: .zero)
        let path = TextToPath.path(for: spec)

        #expect(!path.isEmpty)
    }

    @Test("Positives Tracking vergrössert die Gesamtbreite")
    func trackingIncreasesWidth() {
        var withoutTracking = TextSpec(string: "AVAV", fontName: "Helvetica", fontSize: 72, origin: .zero)
        withoutTracking.tracking = 0
        var withTracking = withoutTracking
        withTracking.tracking = 20

        let narrowPath = TextToPath.path(for: withoutTracking)
        let widePath = TextToPath.path(for: withTracking)

        #expect(widePath.bounds.width > narrowPath.bounds.width)
    }

    @Test("wordSpacing vergrössert die Breite bei Text mit Leerzeichen")
    func wordSpacingIncreasesWidthWithSpace() {
        var withoutSpacing = TextSpec(string: "A A", fontName: "Helvetica", fontSize: 72, origin: .zero)
        withoutSpacing.wordSpacing = 0
        var withSpacing = withoutSpacing
        withSpacing.wordSpacing = 30

        let narrowAdvance = TextToPath.advance(for: withoutSpacing)
        let wideAdvance = TextToPath.advance(for: withSpacing)

        #expect(wideAdvance > narrowAdvance)
    }

    @Test("wordSpacing verändert die Breite bei Text ohne Leerzeichen nicht")
    func wordSpacingDoesNotAffectWidthWithoutSpace() {
        var withoutSpacing = TextSpec(string: "AVA", fontName: "Helvetica", fontSize: 72, origin: .zero)
        withoutSpacing.wordSpacing = 0
        var withSpacing = withoutSpacing
        withSpacing.wordSpacing = 30

        let plainAdvance = TextToPath.advance(for: withoutSpacing)
        let spacedAdvance = TextToPath.advance(for: withSpacing)

        #expect(plainAdvance == spacedAdvance)
    }

    @Test("Grössere Schriftgrösse ergibt einen entsprechend grösseren Hüllrahmen")
    func largerFontSizeProducesLargerBounds() {
        let small = TextSpec(string: "H", fontName: "Helvetica", fontSize: 72, origin: .zero)
        let large = TextSpec(string: "H", fontName: "Helvetica", fontSize: 144, origin: .zero)

        let smallHeight = TextToPath.path(for: small).bounds.height
        let largeHeight = TextToPath.path(for: large).bounds.height

        let ratio = largeHeight / smallHeight
        #expect(ratio > 1.8 && ratio < 2.2, "Verhältnis war \(ratio)")
    }

    @Test("Pfad beginnt waagrecht nahe origin.x")
    func pathStartsNearOriginX() {
        let spec = TextSpec(string: "Hallo", fontName: "Helvetica", fontSize: 72, origin: CGPoint(x: 50, y: 0))
        let path = TextToPath.path(for: spec)

        #expect(path.bounds.minX >= 50 - 5)
        #expect(path.bounds.minX < 50 + 20)
    }
}
