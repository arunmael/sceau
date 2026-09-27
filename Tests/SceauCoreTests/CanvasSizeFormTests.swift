import CoreGraphics
import Testing

@testable import SceauCore

/// Zustand des Dialogs „Leinwandgrösse ändern": welche Vorlage angezeigt
/// wird, wie Vorlage und Eingabefelder zusammenspielen, und wann „Anwenden"
/// möglich ist.
@Suite("Leinwandgrösse — Dialogzustand")
struct CanvasSizeFormTests {

    private func preset(_ name: String) throws -> ArtboardPreset {
        try #require(ArtboardPreset.all.first { $0.name == name })
    }

    @Test("Passt die aktuelle Grösse zu einer Vorlage, ist sie vorausgewählt")
    func initialPresetMatches() throws {
        let form = CanvasSizeForm(size: CGSize(width: 3508, height: 2480))
        #expect(form.preset == (try preset("A4 quer")))
        #expect(form.width == 3508)
        #expect(form.height == 2480)
    }

    @Test("Sonst ist „Eigene Grösse“ ausgewählt")
    func initialCustom() {
        let form = CanvasSizeForm(size: CGSize(width: 777, height: 333))
        #expect(form.preset == nil)
    }

    @Test("Krumme Grössen werden auf ganze Pixel gerundet")
    func initialRounds() {
        let form = CanvasSizeForm(size: CGSize(width: 100.4, height: 99.6))
        #expect(form.width == 100)
        #expect(form.height == 100)
    }

    @Test("Eine Vorlage wählen übernimmt ihre Masse")
    func choosePreset() throws {
        var form = CanvasSizeForm(size: CGSize(width: 3508, height: 2480))
        form.choose(try preset("A5 hoch"))
        #expect(form.width == 1748)
        #expect(form.height == 2480)
        #expect(form.preset == (try preset("A5 hoch")))
    }

    @Test("Gewählte Vorlage bleibt, auch wenn eine andere dieselbe Grösse hat")
    func chosenPresetStaysAmongDuplicates() throws {
        // „Profilbild" und „Quadrat 512" sind beide 512×512.
        var form = CanvasSizeForm(size: CGSize(width: 100, height: 100))
        form.choose(try preset("Quadrat 512"))
        #expect(form.preset == (try preset("Quadrat 512")))
    }

    @Test("Masse von Hand ändern wechselt auf „Eigene Grösse“")
    func editingSwitchesToCustom() throws {
        var form = CanvasSizeForm(size: CGSize(width: 1080, height: 1080))
        form.width = 1000
        #expect(form.preset == nil)
    }

    @Test("Masse von Hand auf eine Vorlage treffen wählt diese")
    func editingOntoPresetSelectsIt() throws {
        var form = CanvasSizeForm(size: CGSize(width: 1080, height: 1000))
        form.height = 1920
        #expect(form.preset == (try preset("Story")))
    }

    @Test("„Eigene Grösse“ wählen behält die Masse")
    func chooseCustomKeepsSize() {
        var form = CanvasSizeForm(size: CGSize(width: 1920, height: 1080))
        form.choose(nil)
        #expect(form.preset == nil)
        #expect(form.width == 1920)
        #expect(form.height == 1080)
    }

    @Test("Absurde Grössen aus einer beschädigten Datei stürzen nicht ab")
    func absurdSizes() {
        let huge = CanvasSizeForm(size: CGSize(width: 1e30, height: .infinity))
        #expect(huge.size == nil)
        let nan = CanvasSizeForm(size: CGSize(width: CGFloat.nan, height: -1e30))
        #expect(nan.size == nil)
    }

    @Test("Nur positive Masse bis zur Obergrenze sind anwendbar")
    func validation() {
        var form = CanvasSizeForm(size: CGSize(width: 500, height: 400))
        #expect(form.size == CGSize(width: 500, height: 400))

        form.width = 0
        #expect(form.size == nil)
        form.width = -5
        #expect(form.size == nil)
        form.width = CanvasSizeForm.maximumLength + 1
        #expect(form.size == nil)
        form.width = CanvasSizeForm.maximumLength
        #expect(form.size == CGSize(width: CanvasSizeForm.maximumLength, height: 400))
    }
}
