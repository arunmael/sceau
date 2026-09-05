import CoreGraphics
import Foundation

/// Einstellungen für den SVG-Export.
public struct SVGExportOptions: Sendable {
    /// Nachkommastellen für Koordinaten. Vorgabe 3 — genug für Icon-Arbeit,
    /// hält die Datei aber klein.
    public var decimals: Int
    /// Wenn true, wird der Inhalt eingerückt und umgebrochen.
    public var prettyPrinted: Bool

    public init(decimals: Int = 3, prettyPrinted: Bool = true) {
        self.decimals = decimals
        self.prettyPrinted = prettyPrinted
    }
}

/// Übersetzt ein ``Document`` in eigenständiges, gültiges SVG.
///
/// Es gibt kein natives SVG-Export-API in AppKit (anders als bei PDF, das über
/// `CGContext` praktisch geschenkt ist) — dieser Konverter übernimmt genau
/// diese Übersetzung von internen Pfad-/Formdaten in SVG-Pfad-Strings.
///
/// Da das Dokumentkoordinatensystem (Ursprung links oben, Y wächst nach unten)
/// bewusst identisch zu SVG gewählt wurde, übernimmt der Export sämtliche
/// Koordinaten unverändert — keine Spiegelung, keine Transformation.
public enum SVGExporter {

    /// Baut das vollständige, eigenständige SVG-Dokument.
    public static func export(_ document: Document, options: SVGExportOptions = .init()) -> String {
        var context = RenderContext(decimals: options.decimals, pretty: options.prettyPrinted)

        var body = ""
        let background = backgroundRectXML(document.artboard, context: context)
        if let background {
            body += context.line(background, indent: 1)
        }
        for node in document.nodes {
            body += render(node, context: &context, indent: 1)
        }

        let width = format(document.artboard.size.width, decimals: options.decimals)
        let height = format(document.artboard.size.height, decimals: options.decimals)
        let viewBox = "0 0 \(width) \(height)"

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        xml += context.pretty ? "\n" : ""
        xml += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"\(viewBox)\">"
        xml += context.pretty ? "\n" : ""

        if !context.defs.isEmpty {
            xml += context.line("<defs>", indent: 1)
            for def in context.defs {
                xml += context.line(def, indent: 2)
            }
            xml += context.line("</defs>", indent: 1)
        }

        xml += body
        xml += "</svg>"
        xml += context.pretty ? "\n" : ""
        return xml
    }

    /// Nur die Pfaddaten (das `d`-Attribut) einer Kontur.
    ///
    /// Gerade Segmente (``CubicSegment/isLine``) werden als `L` ausgegeben statt
    /// als entartetes `C` — das halbiert die Dateigrösse bei Polygonen und ist
    /// bei streng geradlinigen Formen (Rechteck, Polygon, Stern) der Regelfall.
    public static func pathData(_ path: VectorPath, decimals: Int = 3) -> String {
        var parts: [String] = []
        for subpath in path.subpaths {
            guard let first = subpath.anchors.first else { continue }
            parts.append("M\(coord(first.point, decimals: decimals))")
            let segments = subpath.segments
            // Eine gerade Rückkehr zum Anfang übernimmt `Z` bereits; eine
            // Kurve muss dagegen vor dem Schliessen ausdrücklich erhalten bleiben.
            let omittedSegments = subpath.isClosed && segments.last?.isLine == true ? 1 : 0
            for segment in segments.dropLast(omittedSegments) {
                if segment.isLine {
                    parts.append("L\(coord(segment.end, decimals: decimals))")
                } else {
                    parts.append(
                        "C\(coord(segment.control1, decimals: decimals)) "
                            + "\(coord(segment.control2, decimals: decimals)) "
                            + "\(coord(segment.end, decimals: decimals))"
                    )
                }
            }
            if subpath.isClosed {
                parts.append("Z")
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Knoten

    private static func render(_ node: Node, context: inout RenderContext, indent: Int) -> String {
        guard node.isVisible else { return "" }

        switch node.content {
        case let .group(children):
            let attrs = styleAttributes(for: node, context: &context)
            var xml = context.line("<g\(attrs)>", indent: indent)
            for child in children {
                xml += render(child, context: &context, indent: indent + 1)
            }
            xml += context.line("</g>", indent: indent)
            return xml

        case .shape, .path, .text:
            // Auch Text wird als Kontur geschrieben, nie als <text>-Element:
            // Ein Empfänger ohne die verwendete Schrift bekäme sonst ein
            // anderes Logo zu sehen. Genau dafür gibt es „Text in Pfade
            // umwandeln".
            let path = NodeGeometry.path(for: node)
            guard !path.isEmpty else { return "" }
            let d = pathData(path, decimals: context.decimals)
            let attrs = styleAttributes(for: node, context: &context)
            return context.line("<path d=\"\(xmlEscape(d))\"\(attrs)/>", indent: indent)
        }
    }

    // MARK: - Stil-Attribute

    /// Baut die gemeinsamen Attribute (Name, Füllung, Kontur, Füllregel,
    /// Deckkraft), die für jede Art von Knoten-Element gelten — `<path>`
    /// ebenso wie `<g>`.
    private static func styleAttributes(for node: Node, context: inout RenderContext) -> String {
        var attrs: [(String, String)] = []
        attrs.append(("id", xmlEscape(node.name)))

        attrs.append(contentsOf: paintAttributes(node.style.fill, prefix: "fill", context: &context))

        if node.style.fillRule == .evenOdd {
            attrs.append(("fill-rule", "evenodd"))
        }

        if let stroke = node.style.stroke, stroke.isVisible {
            attrs.append(contentsOf: paintAttributes(stroke.paint, prefix: "stroke", context: &context))
            attrs.append(("stroke-width", format(stroke.width, decimals: context.decimals)))
            attrs.append(("stroke-linecap", stroke.cap.rawValue))
            attrs.append(("stroke-linejoin", stroke.join.rawValue))
            if !stroke.dash.isEmpty {
                let dash = stroke.dash.map { format($0, decimals: context.decimals) }.joined(separator: ",")
                attrs.append(("stroke-dasharray", dash))
            }
        }

        if node.style.opacity < 1 {
            attrs.append(("opacity", format(node.style.opacity, decimals: max(context.decimals, 2))))
        }

        if let shadow = node.style.shadow {
            let id = context.registerShadowFilter(shadow)
            attrs.append(("filter", "url(#\(id))"))
        }

        guard !attrs.isEmpty else { return "" }
        return " " + attrs.map { "\($0.0)=\"\($0.1)\"" }.joined(separator: " ")
    }

    /// Attribute für eine Füllung oder Kontur (`fill`/`stroke` plus
    /// zugehöriger `-opacity`). Verläufe werden dabei als `<defs>`-Eintrag
    /// registriert und per `url(#id)` referenziert.
    private static func paintAttributes(
        _ paint: Paint,
        prefix: String,
        context: inout RenderContext
    ) -> [(String, String)] {
        switch paint {
        case .none:
            return [(prefix, "none")]

        case let .solid(color):
            var result: [(String, String)] = [(prefix, hex(color))]
            if color.alpha < 1 {
                result.append(("\(prefix)-opacity", format(color.alpha, decimals: max(context.decimals, 2))))
            }
            return result

        case let .linearGradient(gradient):
            let id = context.registerLinearGradient(gradient)
            return [(prefix, "url(#\(id))")]

        case let .radialGradient(gradient):
            let id = context.registerRadialGradient(gradient)
            return [(prefix, "url(#\(id))")]

        case let .pattern(fill):
            let id = context.registerPattern(fill)
            return [(prefix, "url(#\(id))")]
        }
    }

    private static func backgroundRectXML(_ artboard: Artboard, context: RenderContext) -> String? {
        guard artboard.background.alpha > 0 else { return nil }
        let width = format(artboard.size.width, decimals: context.decimals)
        let height = format(artboard.size.height, decimals: context.decimals)
        var xml = "<rect x=\"0\" y=\"0\" width=\"\(width)\" height=\"\(height)\" fill=\"\(hex(artboard.background))\""
        if artboard.background.alpha < 1 {
            xml += " fill-opacity=\"\(format(artboard.background.alpha, decimals: max(context.decimals, 2)))\""
        }
        xml += "/>"
        return xml
    }

    // MARK: - Verläufe

    private static func gradientStopsXML(_ gradient: Gradient, context: RenderContext) -> String {
        gradient.stops.map { stop in
            var xml = "<stop offset=\"\(format(stop.location, decimals: max(context.decimals, 2)))\" stop-color=\"\(hex(stop.color))\""
            if stop.color.alpha < 1 {
                xml += " stop-opacity=\"\(format(stop.color.alpha, decimals: max(context.decimals, 2)))\""
            }
            xml += "/>"
            return xml
        }.joined()
    }

    // MARK: - Formatierung

    /// Formatiert eine Fliesskommazahl mit fester Nachkommastellenzahl, aber
    /// ohne überflüssige Nullen (z. B. `10` statt `10.000`, `1.5` statt `1.500`).
    private static func format(_ value: CGFloat, decimals: Int) -> String {
        let clampedDecimals = max(0, decimals)
        var text = String(format: "%.\(clampedDecimals)f", Double(value))
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return text
    }

    private static func coord(_ point: CGPoint, decimals: Int) -> String {
        "\(format(point.x, decimals: decimals)),\(format(point.y, decimals: decimals))"
    }

    /// Erkennt PNG/JPEG an der Signatur der ersten Bytes statt an einer
    /// mitgeführten, potenziell veralteten Typangabe — Bilddaten sind im
    /// Dokumentmodell nur `Data`, ihr tatsächlicher Inhalt entscheidet.
    private static func imageMIMEType(for data: Data) -> String {
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        if data.starts(with: pngSignature) { return "image/png" }
        if data.count >= 2, data[data.startIndex] == 0xFF, data[data.startIndex + 1] == 0xD8 {
            return "image/jpeg"
        }
        return "image/png"
    }

    private static func hex(_ color: RGBAColor) -> String {
        let r = Int((color.red * 255).rounded())
        let g = Int((color.green * 255).rounded())
        let b = Int((color.blue * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    /// Maskiert die Zeichen, die in einem XML-Attributwert (mit doppelten
    /// Anführungszeichen) Sonderbedeutung haben.
    private static func xmlEscape(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        return result
    }

    // MARK: - Renderzustand

    /// Trägt den laufenden Zustand während des Exports: Einrückung, das
    /// `<defs>`-Sammelbecken für Verläufe und deren fortlaufende ID-Vergabe.
    ///
    /// Ein eigener Typ statt loser `inout`-Parameter, weil beim Rekursieren
    /// über verschachtelte Gruppen mehrere Werte gemeinsam durchgereicht
    /// werden müssen.
    private struct RenderContext {
        let decimals: Int
        let pretty: Bool
        var defs: [String] = []
        private var gradientCounter = 0

        init(decimals: Int, pretty: Bool) {
            self.decimals = decimals
            self.pretty = pretty
        }

        mutating func registerLinearGradient(_ gradient: Gradient) -> String {
            let id = nextGradientID()
            var xml = "<linearGradient id=\"\(id)\" gradientUnits=\"objectBoundingBox\""
            xml += " x1=\"\(SVGExporter.format(gradient.start.x, decimals: max(decimals, 2)))\""
            xml += " y1=\"\(SVGExporter.format(gradient.start.y, decimals: max(decimals, 2)))\""
            xml += " x2=\"\(SVGExporter.format(gradient.end.x, decimals: max(decimals, 2)))\""
            xml += " y2=\"\(SVGExporter.format(gradient.end.y, decimals: max(decimals, 2)))\""
            xml += ">"
            xml += SVGExporter.gradientStopsXML(gradient, context: self)
            xml += "</linearGradient>"
            defs.append(xml)
            return id
        }

        /// Trägt eine Musterfüllung als `<pattern>` mit eingebettetem
        /// Base64-Bild ein. `patternUnits="userSpaceOnUse"` statt der bei
        /// Verläufen verwendeten `objectBoundingBox`, weil die Kachelgrösse
        /// in Dokumentpunkten gemeint ist, nicht als Anteil des Hüllrahmens
        /// der jeweiligen Form — sonst sähe dieselbe Musterfüllung auf zwei
        /// unterschiedlich grossen Formen unterschiedlich gekachelt aus.
        mutating func registerPattern(_ fill: PatternFill) -> String {
            let id = nextGradientID(prefix: "pattern")
            let width = SVGExporter.format(fill.tileSize.width, decimals: max(decimals, 2))
            let height = SVGExporter.format(fill.tileSize.height, decimals: max(decimals, 2))
            let base64 = fill.imageData.base64EncodedString()
            let mime = SVGExporter.imageMIMEType(for: fill.imageData)

            var xml = "<pattern id=\"\(id)\" patternUnits=\"userSpaceOnUse\""
            xml += " width=\"\(width)\" height=\"\(height)\""
            if fill.rotation != 0 {
                let degrees = SVGExporter.format(fill.rotation * 180 / .pi, decimals: max(decimals, 2))
                xml += " patternTransform=\"rotate(\(degrees))\""
            }
            xml += ">"
            xml += "<image href=\"data:\(mime);base64,\(base64)\" width=\"\(width)\" height=\"\(height)\"/>"
            xml += "</pattern>"
            defs.append(xml)
            return id
        }

        /// Trägt einen Schlagschatten als `<filter>` mit `feDropShadow` ein —
        /// das einzige SVG-Element, das genau unser Modell (Versatz, Blur,
        /// Farbe inkl. Alpha) 1:1 abbildet, ohne über mehrere Primitive
        /// (feGaussianBlur + feOffset + feFlood + feComposite) zusammengesetzt
        /// werden zu müssen.
        mutating func registerShadowFilter(_ shadow: Shadow) -> String {
            let id = nextGradientID(prefix: "shadow")
            let dx = SVGExporter.format(shadow.offset.width, decimals: max(decimals, 2))
            let dy = SVGExporter.format(shadow.offset.height, decimals: max(decimals, 2))
            // SVG erwartet eine Standardabweichung, unser Modell einen
            // Blur-Radius — der gängige Umrechnungsfaktor ist 1/2.
            let stdDeviation = SVGExporter.format(shadow.blurRadius / 2, decimals: max(decimals, 2))
            let color = SVGExporter.hex(shadow.color)
            let opacity = SVGExporter.format(shadow.color.alpha, decimals: max(decimals, 2))

            var xml = "<filter id=\"\(id)\" x=\"-50%\" y=\"-50%\" width=\"200%\" height=\"200%\">"
            xml += "<feDropShadow dx=\"\(dx)\" dy=\"\(dy)\" stdDeviation=\"\(stdDeviation)\""
            xml += " flood-color=\"\(color)\" flood-opacity=\"\(opacity)\"/>"
            xml += "</filter>"
            defs.append(xml)
            return id
        }

        mutating func registerRadialGradient(_ gradient: Gradient) -> String {
            let id = nextGradientID()
            let dx = gradient.end.x - gradient.start.x
            let dy = gradient.end.y - gradient.start.y
            let radius = (dx * dx + dy * dy).squareRoot()
            var xml = "<radialGradient id=\"\(id)\" gradientUnits=\"objectBoundingBox\""
            xml += " cx=\"\(SVGExporter.format(gradient.start.x, decimals: max(decimals, 2)))\""
            xml += " cy=\"\(SVGExporter.format(gradient.start.y, decimals: max(decimals, 2)))\""
            xml += " r=\"\(SVGExporter.format(radius, decimals: max(decimals, 2)))\""
            xml += ">"
            xml += SVGExporter.gradientStopsXML(gradient, context: self)
            xml += "</radialGradient>"
            defs.append(xml)
            return id
        }

        private mutating func nextGradientID(prefix: String = "gradient") -> String {
            defer { gradientCounter += 1 }
            return "\(prefix)\(gradientCounter)"
        }

        /// Baut eine Zeile mit passender Einrückung; ohne `prettyPrinted` wird
        /// nur der reine Inhalt zurückgegeben (kein Umbruch, keine Leerzeichen).
        func line(_ content: String, indent: Int) -> String {
            guard pretty else { return content }
            return String(repeating: "  ", count: indent) + content + "\n"
        }
    }
}
