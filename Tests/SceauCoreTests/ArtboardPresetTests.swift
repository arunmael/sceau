import CoreGraphics
import Testing

@testable import SceauCore

/// Vorgabegrössen der Zeichenfläche: neben Icons auch Social-Media-Formate
/// und Papierformate (A-Reihe bei 300 dpi).
@Suite("Zeichenfläche — Vorgabegrössen")
struct ArtboardPresetTests {

    private func size(of name: String) -> CGSize? {
        ArtboardPreset.all.first { $0.name == name }?.size
    }

    @Test("Social-Media-Formate")
    func socialMedia() {
        #expect(size(of: "Quadrat") == CGSize(width: 1080, height: 1080))
        #expect(size(of: "Beitrag hoch") == CGSize(width: 1080, height: 1350))
        #expect(size(of: "Story") == CGSize(width: 1080, height: 1920))
        #expect(size(of: "Full HD") == CGSize(width: 1920, height: 1080))
    }

    @Test("Papierformate bei 300 dpi")
    func paper() {
        #expect(size(of: "A4 hoch") == CGSize(width: 2480, height: 3508))
        #expect(size(of: "A4 quer") == CGSize(width: 3508, height: 2480))
        #expect(size(of: "A5 hoch") == CGSize(width: 1748, height: 2480))
        #expect(size(of: "A5 quer") == CGSize(width: 2480, height: 1748))
        #expect(size(of: "A3 hoch") == CGSize(width: 3508, height: 4961))
    }

    @Test("Bisherige Icon-Vorgaben bleiben erhalten")
    func iconPresetsKept() {
        #expect(size(of: "App-Icon") == CGSize(width: 1024, height: 1024))
        #expect(size(of: "Favicon") == CGSize(width: 64, height: 64))
    }

    @Test("Gruppen decken genau alle Vorgaben ab, Namen sind eindeutig")
    func groupsCoverAll() {
        let grouped = ArtboardPreset.groups.flatMap(\.presets)
        #expect(grouped == ArtboardPreset.all)
        #expect(Set(ArtboardPreset.all.map(\.id)).count == ArtboardPreset.all.count)
        #expect(ArtboardPreset.groups.map(\.title) == ["Icons", "Social Media", "Papier (300 dpi)"])
    }
}
