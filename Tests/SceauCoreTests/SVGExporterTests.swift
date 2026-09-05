import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

/// Prüft `SVGExporter` gegen einen echten XML-Parser (`XMLDocument`), nicht
/// nur gegen Zeichenkettenvergleiche — siehe `agent-rules.md` Abschnitt 4:
/// Export-Korrektheit hat Vorrang, und Wohlgeformtheit ist nur gegen ein
/// unabhängiges Werkzeug verlässlich zu prüfen, nicht gegen den eigenen Code.
@Suite("SVGExporter")
struct SVGExporterTests {

    /// Wirft, wenn `svg` kein wohlgeformtes XML ist.
    private func assertWellFormed(_ svg: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        do {
            _ = try XMLDocument(xmlString: svg, options: [])
        } catch {
            Issue.record("SVG ist kein wohlgeformtes XML: \(error)\n---\n\(svg)", sourceLocation: sourceLocation)
        }
    }

    private func rectangleDocument(y: CGFloat = 10) -> Document {
        var document = Document(artboard: Artboard(size: CGSize(width: 100, height: 50)))
        document.nodes = [
            Node(shape: .rectangle(frame: CGRect(x: 10, y: y, width: 30, height: 20), cornerRadius: 0))
        ]
        return document
    }

    @Test("Rechteck-Dokument erzeugt viewBox und Pfad mit M/L/Z")
    func rectangleProducesViewBoxAndPath() throws {
        let svg = SVGExporter.export(rectangleDocument())

        #expect(svg.contains(#"viewBox="0 0 100 50""#))
        #expect(svg.contains("<path"))
        #expect(svg.contains("M"))
        #expect(svg.contains("L"))
        #expect(svg.contains("Z"))
        try assertWellFormed(svg)
    }

    @Test("Koordinaten werden nicht gespiegelt")
    func coordinatesAreNotFlipped() throws {
        let svg = SVGExporter.export(rectangleDocument(y: 10))

        // Y-Achse wächst nach unten, identisch zu SVG — y=10 muss als 10
        // erscheinen, nicht als höhe(50) - 10 - 20(höhe des Rechtecks) = 20.
        #expect(svg.contains("10"))
        // Der erste Anker des Rechtecks liegt bei (10,10) — nicht gespiegelt
        // wäre der Pfad also mit "M10,10" o.ä. beginnend, niemals mit y=40.
        #expect(!svg.contains("M10,40"))
        try assertWellFormed(svg)
    }

    @Test("Gerade Segmente werden als L, nicht als C exportiert")
    func straightSegmentsUseLNotC() {
        let path = VectorPath(subpath: Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10)
        ]))
        let d = SVGExporter.pathData(path)

        #expect(!d.contains("C"))
        #expect(d.contains("L"))
    }

    @Test("Verlauf erzeugt defs-Block mit referenzierter ID")
    func gradientProducesDefsWithReferencedID() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 50, height: 50)))
        let gradient = Gradient(
            stops: [
                GradientStop(color: .black, location: 0),
                GradientStop(color: .white, location: 1)
            ],
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 1, y: 1)
        )
        var style = Style()
        style.fill = .linearGradient(gradient)
        document.nodes = [
            Node(shape: .ellipse(frame: CGRect(x: 0, y: 0, width: 50, height: 50)), style: style)
        ]

        let svg = SVGExporter.export(document)
        try assertWellFormed(svg)

        #expect(svg.contains("<defs>"))
        #expect(svg.contains("<linearGradient"))

        // Die per fill="url(#…)" referenzierte ID muss tatsächlich als
        // Element-ID im Dokument existieren.
        guard let urlRange = svg.range(of: #"fill="url(#"#) else {
            Issue.record("kein fill=\"url(#…)\" gefunden")
            return
        }
        let afterURL = svg[urlRange.upperBound...]
        guard let closeParen = afterURL.firstIndex(of: ")") else {
            Issue.record("url(#…) nicht geschlossen")
            return
        }
        let referencedID = String(afterURL[afterURL.startIndex..<closeParen])
        #expect(svg.contains(#"id="\#(referencedID)""#))
    }

    @Test("Musterfüllung erzeugt defs-Block mit eingebettetem Bild und referenzierter ID")
    func patternProducesDefsWithEmbeddedImage() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 50, height: 50)))
        // Ein einzelnes, minimales 1x1-PNG genügt — es geht hier um die
        // XML-Struktur, nicht um den Bildinhalt.
        let onePixelPNG = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82
        ])
        var style = Style()
        style.fill = .pattern(PatternFill(imageData: onePixelPNG, tileSize: CGSize(width: 10, height: 10)))
        document.nodes = [
            Node(shape: .ellipse(frame: CGRect(x: 0, y: 0, width: 50, height: 50)), style: style)
        ]

        let svg = SVGExporter.export(document)
        try assertWellFormed(svg)

        #expect(svg.contains("<pattern"))
        #expect(svg.contains("<image"))
        #expect(svg.contains("data:image/png;base64,"))
    }

    @Test("Unsichtbare Knoten fehlen in der Ausgabe")
    func invisibleNodesAreOmitted() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 50, height: 50)))
        var hidden = Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0))
        hidden.name = "VersteckteForm"
        hidden.isVisible = false
        document.nodes = [hidden]

        let svg = SVGExporter.export(document)
        try assertWellFormed(svg)

        #expect(!svg.contains("VersteckteForm"))
        #expect(!svg.contains("<path"))
    }

    @Test("Name mit & und \" bricht das XML nicht")
    func specialCharactersInNameDoNotBreakXML() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 50, height: 50)))
        var node = Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0))
        node.name = "Katze & Hund \"Bello\""
        document.nodes = [node]

        let svg = SVGExporter.export(document)
        try assertWellFormed(svg)
    }

    @Test("Gruppen erzeugen verschachtelte g-Elemente")
    func groupsProduceNestedGElements() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 50, height: 50)))
        document.nodes = [
            Node(
                name: "Aussen",
                content: .group(children: [
                    Node(
                        name: "Innen",
                        content: .group(children: [
                            Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0))
                        ])
                    )
                ])
            )
        ]

        let svg = SVGExporter.export(document)
        try assertWellFormed(svg)

        let groupCount = svg.components(separatedBy: "<g").count - 1
        #expect(groupCount == 2)
    }

    @Test("Text wird als Kontur exportiert, nie als text-Element")
    func textIsExportedAsOutlines() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 200, height: 100)))
        document.nodes = [
            Node(
                name: "Titel",
                content: .text(TextSpec(
                    string: "Hallo",
                    fontName: "Helvetica",
                    fontSize: 48,
                    origin: CGPoint(x: 10, y: 70)
                ))
            )
        ]

        let svg = SVGExporter.export(document)
        try assertWellFormed(svg)

        // Ein <text>-Element würde beim Empfänger mit einer anderen Schrift
        // gesetzt — genau das soll der Export verhindern.
        #expect(!svg.contains("<text"))
        #expect(svg.contains("<path"), "der Schriftzug muss als Pfad im SVG stehen")
    }

    @Test("Leerer Text erzeugt kein leeres Pfad-Element")
    func emptyTextProducesNoElement() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 50, height: 50)))
        document.nodes = [Node(name: "Leer", content: .text(TextSpec(string: "")))]

        let svg = SVGExporter.export(document)
        try assertWellFormed(svg)

        #expect(!svg.contains("<path"))
    }

    @Test("decimals wirkt auf die Ausgabelänge")
    func decimalsAffectOutputLength() {
        let path = VectorPath(subpath: Subpath(
            anchors: [
                Anchor(corner: CGPoint(x: 0.123456, y: 0)),
                Anchor(corner: CGPoint(x: 10.654321, y: 0)),
                Anchor(corner: CGPoint(x: 10, y: 10.987654))
            ],
            isClosed: true
        ))

        let highPrecision = SVGExporter.pathData(path, decimals: 6)
        let lowPrecision = SVGExporter.pathData(path, decimals: 1)

        #expect(highPrecision.count > lowPrecision.count)
    }

    @Test("Zahlen ohne überflüssige Nullen")
    func numbersHaveNoTrailingZeros() {
        let path = VectorPath(subpath: Subpath(closedPolygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10)
        ]))
        let d = SVGExporter.pathData(path)

        #expect(!d.contains("10.000"))
        #expect(d.contains("10"))
    }

    @Test("Hintergrund wird nur ausgegeben, wenn nicht vollständig transparent")
    func backgroundOnlyEmittedWhenNotFullyTransparent() throws {
        let transparentDocument = Document(artboard: Artboard(size: CGSize(width: 20, height: 20), background: .clear))
        let opaqueDocument = Document(
            artboard: Artboard(size: CGSize(width: 20, height: 20), background: RGBAColor(red: 1, green: 0, blue: 0))
        )

        let transparentSVG = SVGExporter.export(transparentDocument)
        let opaqueSVG = SVGExporter.export(opaqueDocument)

        try assertWellFormed(transparentSVG)
        try assertWellFormed(opaqueSVG)

        #expect(!transparentSVG.contains("<rect"))
        #expect(opaqueSVG.contains("<rect"))
        #expect(opaqueSVG.contains("#ff0000"))
    }

    @Test("Fläche none wird als fill=\"none\" exportiert")
    func noneFillExportsAsFillNone() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 20, height: 20)))
        var style = Style()
        style.fill = .none
        document.nodes = [
            Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0), style: style)
        ]

        let svg = SVGExporter.export(document)
        try assertWellFormed(svg)
        #expect(svg.contains(#"fill="none""#))
    }

    @Test("Sichtbare Kontur exportiert stroke-Attribute")
    func visibleStrokeExportsStrokeAttributes() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 20, height: 20)))
        var style = Style()
        style.stroke = Stroke(paint: .solid(.black), width: 2, cap: .round, join: .round)
        document.nodes = [
            Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0), style: style)
        ]

        let svg = SVGExporter.export(document)
        try assertWellFormed(svg)

        #expect(svg.contains(##"stroke="#000000""##))
        #expect(svg.contains(#"stroke-width="2""#))
        #expect(svg.contains(#"stroke-linecap="round""#))
        #expect(svg.contains(#"stroke-linejoin="round""#))
    }

    @Test("evenodd wird nur ausgegeben, wenn abweichend von nonzero")
    func evenOddOnlyEmittedWhenNonDefault() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 20, height: 20)))
        var evenOddStyle = Style()
        evenOddStyle.fillRule = .evenOdd
        document.nodes = [
            Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0), style: evenOddStyle),
            Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0))
        ]

        let svg = SVGExporter.export(document)
        try assertWellFormed(svg)

        #expect(svg.contains(#"fill-rule="evenodd""#))
        // Der zweite Knoten hat die Vorgabe (nonzero) — dafür darf kein
        // fill-rule-Attribut erscheinen. Da beide Knoten im selben Dokument
        // liegen, prüfen wir, dass evenodd nur einmal auftaucht.
        let occurrences = svg.components(separatedBy: #"fill-rule="evenodd""#).count - 1
        #expect(occurrences == 1)
    }

    @Test("Knoten-Deckkraft unter 1 erzeugt opacity-Attribut")
    func nodeOpacityBelowOneExportsOpacityAttribute() throws {
        var document = Document(artboard: Artboard(size: CGSize(width: 20, height: 20)))
        var style = Style()
        style.opacity = 0.5
        document.nodes = [
            Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0), style: style)
        ]

        let svg = SVGExporter.export(document)
        try assertWellFormed(svg)
        #expect(svg.contains(#"opacity="0.5""#))
    }
}

@Suite("SVGExporter — knappe Pfaddaten")
struct SVGCompactPathTests {

    @Test("Ein geschlossener Polyzug endet mit Z, ohne die Schlussstrecke doppelt zu schreiben")
    func closingLineIsNotWrittenTwice() {
        let path = VectorPath(subpath: Subpath(closedPolygon: [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 110, y: 10),
            CGPoint(x: 110, y: 60),
            CGPoint(x: 10, y: 60)
        ]))

        let d = SVGExporter.pathData(path)

        // `Z` zieht die Linie zum Anfangspunkt bereits selbst; ein zusätzliches
        // L dorthin bläht jede geschlossene Form unnötig auf.
        #expect(d.hasSuffix("Z"))
        #expect(d.filter { $0 == "L" }.count == 3, "erwartet drei Strecken, war: \(d)")
        #expect(!d.contains("L10,10Z"), "die Schlussstrecke steht doppelt: \(d)")
    }

    @Test("Eine gekrümmte Schlussstrecke bleibt erhalten")
    func closingCurveIsKept() {
        // Der letzte Anker hat einen ausgehenden Griff, der erste einen
        // eingehenden — die Rückkehr zum Anfang ist damit eine echte Kurve und
        // darf nicht durch Z ersetzt werden.
        let anchors = [
            Anchor(
                point: CGPoint(x: 0, y: 0),
                controlIn: CGPoint(x: -30, y: 40),
                controlOut: CGPoint(x: 30, y: -40)
            ),
            Anchor(
                point: CGPoint(x: 100, y: 0),
                controlIn: CGPoint(x: 70, y: -40),
                controlOut: CGPoint(x: 130, y: 40)
            )
        ]
        let path = VectorPath(subpath: Subpath(anchors: anchors, isClosed: true))

        let d = SVGExporter.pathData(path)
        #expect(d.filter { $0 == "C" }.count == 2, "beide Kurven müssen erhalten bleiben: \(d)")
        #expect(d.hasSuffix("Z"))
    }

    @Test("Ein offener Pfad bekommt kein Z")
    func openPathHasNoClose() {
        let path = VectorPath(subpath: Subpath(
            anchors: [Anchor(corner: .zero), Anchor(corner: CGPoint(x: 10, y: 0))],
            isClosed: false
        ))
        #expect(!SVGExporter.pathData(path).contains("Z"))
    }
}
