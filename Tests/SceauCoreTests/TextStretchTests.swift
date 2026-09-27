import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

/// Text frei in Breite und Höhe ziehen, wie ein Bild — und dabei editierbarer
/// Text bleiben. Grundlage ist ``TextSpec/horizontalScale``: die Schriftgrösse
/// folgt der Höhe, die horizontale Skalierung nimmt den Rest der Breite auf.
@Suite("Text — frei verziehen")
struct TextStretchTests {

    // Mit Leerzeichen und Abständen: auch Zeichen- und Wortabstand müssen
    // beim Ziehen mitgehen, sonst verfehlt die Breite den Zielrahmen.
    private let spec = TextSpec(
        string: "Sce au", fontName: "Helvetica-Bold", fontSize: 100,
        tracking: 5, wordSpacing: 8, origin: CGPoint(x: 50, y: 200)
    )

    private func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.01) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    @Test("Horizontale Skalierung streckt nur die Breite, ab dem Startpunkt")
    func horizontalScaleStretchesWidth() {
        var stretched = spec
        stretched.horizontalScale = 2

        let original = TextToPath.path(for: spec).bounds
        let wide = TextToPath.path(for: stretched).bounds

        #expect(abs(wide.width - original.width * 2) < 0.01)
        #expect(abs(wide.height - original.height) < 0.01)
        #expect(abs(wide.minY - original.minY) < 0.01)
        // Gestreckt wird vom Startpunkt aus, nicht vom Rand der Glyphen.
        #expect(abs((wide.minX - spec.origin.x) - (original.minX - spec.origin.x) * 2) < 0.01)
    }

    @Test("Der Vorschub wird mitgestreckt")
    func advanceScales() {
        var stretched = spec
        stretched.horizontalScale = 0.5
        #expect(abs(TextToPath.advance(for: stretched) - TextToPath.advance(for: spec) * 0.5) < 0.001)
    }

    @Test("Unproportional ziehen bringt den Text genau auf den Zielrahmen")
    func resizeHitsTargetFrame() throws {
        let node = Node(name: "Text", content: .text(spec))
        let source = NodeGeometry.bounds(for: node)
        let target = CGRect(x: source.minX + 10, y: source.minY - 20, width: source.width * 2.5, height: source.height * 0.6)

        let resized = NodeTransform.resized(node, from: source, to: target)

        #expect(isClose(NodeGeometry.bounds(for: resized), target))
        guard case let .text(result) = resized.content else {
            Issue.record("Muss Text bleiben, nicht zu einem Pfad werden")
            return
        }
        #expect(result.string == "Sce au")
    }

    @Test("Proportional ziehen lässt die horizontale Skalierung unverändert")
    func uniformResizeKeepsScale() {
        let node = Node(name: "Text", content: .text(spec))
        let source = NodeGeometry.bounds(for: node)
        let target = CGRect(x: source.minX, y: source.minY, width: source.width * 1.5, height: source.height * 1.5)

        guard case let .text(result) = NodeTransform.resized(node, from: source, to: target).content else { return }
        #expect(abs(result.horizontalScale - 1) < 1e-9)
        #expect(abs(result.fontSize - 150) < 1e-9)
    }

    @Test("Auf null Höhe gezogen entstehen keine unendlichen oder NaN-Werte")
    func zeroHeightStaysFinite() {
        let node = Node(name: "Text", content: .text(spec))
        let source = NodeGeometry.bounds(for: node)
        let target = CGRect(x: source.minX, y: source.minY, width: source.width * 2, height: 0)

        guard case let .text(result) = NodeTransform.resized(node, from: source, to: target).content else { return }
        #expect(result.horizontalScale.isFinite)
        #expect(result.fontSize.isFinite)
        #expect(result.origin.x.isFinite && result.origin.y.isFinite)
    }

    @Test("Ältere Dateien ohne horizontale Skalierung öffnen mit 100 %")
    func decodesLegacyFiles() throws {
        let legacy = """
        {"string":"Alt","fontName":"Helvetica","fontSize":24,"tracking":0,"wordSpacing":0,"origin":[1,2]}
        """
        let decoded = try JSONDecoder().decode(TextSpec.self, from: Data(legacy.utf8))
        #expect(decoded.horizontalScale == 1)
        #expect(decoded.string == "Alt")
        #expect(decoded.origin == CGPoint(x: 1, y: 2))
    }

    @Test("Horizontale Skalierung übersteht Sichern und Öffnen")
    func roundTrip() throws {
        var stretched = spec
        stretched.horizontalScale = 1.75
        let data = try JSONEncoder().encode(stretched)
        #expect(try JSONDecoder().decode(TextSpec.self, from: data) == stretched)
    }
}
