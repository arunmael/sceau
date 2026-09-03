import CoreGraphics

/// Zeichnet ein ``Document`` in einen beliebigen `CGContext` — die gemeinsame
/// Rendergrundlage für PNG- und PDF-Export.
///
/// Bewusst getrennt von `RasterExporter`/`PDFExporter`: Wie ein Kontext
/// entsteht (Bitmap-Puffer vs. PDF-Seite) und wie er letztlich zu `Data` wird,
/// ist reine Export-Mechanik; wie ein Dokumentbaum in Zeichenbefehle übersetzt
/// wird, ist davon unabhängig und für beide Ziele identisch.
public enum DocumentRenderer {

    /// Zeichnet das Dokument in einen Grafikkontext.
    ///
    /// Der Aufrufer hat den Kontext bereits so eingerichtet, dass in
    /// Dokumentkoordinaten (Ursprung links oben, y nach unten) gezeichnet
    /// wird — diese Funktion selbst kennt weder Bitmap- noch PDF-spezifische
    /// Einrichtung und nimmt keine eigene Spiegelung vor.
    public static func draw(_ document: Document, in context: CGContext, drawBackground: Bool) {
        if drawBackground, document.artboard.background.alpha > 0 {
            context.saveGState()
            context.setFillColor(document.artboard.background.cgColor)
            context.fill(document.artboard.frame)
            context.restoreGState()
        }

        for node in document.nodes {
            draw(node, in: context)
        }
    }

    // MARK: - Knoten

    private static func draw(_ node: Node, in context: CGContext) {
        guard node.isVisible, node.style.opacity > 0 else { return }

        if case let .group(children) = node.content {
            context.saveGState()
            context.setAlpha(node.style.opacity)
            for child in children {
                draw(child, in: context)
            }
            context.restoreGState()
            return
        }

        // Textknoten liefern über `NodeGeometry.path(for:)` derzeit einen
        // leeren Pfad (Text-zu-Pfad entsteht parallel in einer eigenen
        // Umsetzung) — sie fallen damit unten bei `path.isEmpty` automatisch
        // weg, ohne dass diese Funktion den Fall gesondert behandeln muss.
        let path = NodeGeometry.path(for: node)
        guard !path.isEmpty else { return }

        context.saveGState()
        context.setAlpha(node.style.opacity)
        drawFill(path, style: node.style, in: context)
        drawStroke(path, style: node.style, in: context)
        context.restoreGState()
    }

    // MARK: - Füllung

    private static func drawFill(_ path: VectorPath, style: Style, in context: CGContext) {
        switch style.fill {
        case .none:
            return

        case let .solid(color):
            context.saveGState()
            context.addPath(path.cgPath)
            context.setFillColor(color.cgColor)
            context.fillPath(using: cgFillRule(style.fillRule))
            context.restoreGState()

        case let .linearGradient(gradient):
            drawGradient(gradient, radial: false, path: path, fillRule: style.fillRule, in: context)

        case let .radialGradient(gradient):
            drawGradient(gradient, radial: true, path: path, fillRule: style.fillRule, in: context)
        }
    }

    /// Zeichnet einen Verlauf, indem der Kontext auf den Pfad geklippt und
    /// darüber der Verlauf gezogen wird — der einzige Weg, mit `CGContext`
    /// eine beliebige Kontur statt eines Rechtecks mit einem Verlauf zu füllen.
    private static func drawGradient(
        _ gradient: Gradient,
        radial: Bool,
        path: VectorPath,
        fillRule: FillRule,
        in context: CGContext
    ) {
        let bounds = path.bounds
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }
        guard let cgGradient = makeCGGradient(gradient) else { return }

        // Start-/Endpunkte des Modells sind auf den Hüllrahmen normalisiert
        // (0…1) — hier auf die tatsächlichen Dokumentkoordinaten der Form
        // umgerechnet.
        let start = CGPoint(
            x: bounds.minX + gradient.start.x * bounds.width,
            y: bounds.minY + gradient.start.y * bounds.height
        )
        let end = CGPoint(
            x: bounds.minX + gradient.end.x * bounds.width,
            y: bounds.minY + gradient.end.y * bounds.height
        )

        context.saveGState()
        context.addPath(path.cgPath)
        context.clip(using: cgFillRule(fillRule))

        if radial {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let radius = (dx * dx + dy * dy).squareRoot()
            context.drawRadialGradient(
                cgGradient,
                startCenter: start, startRadius: 0,
                endCenter: start, endRadius: radius,
                options: [.drawsAfterEndLocation]
            )
        } else {
            context.drawLinearGradient(
                cgGradient,
                start: start, end: end,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        context.restoreGState()
    }

    private static func makeCGGradient(_ gradient: Gradient) -> CGGradient? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = gradient.stops.map { $0.color.cgColor } as CFArray
        let locations = gradient.stops.map { CGFloat($0.location) }
        return CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)
    }

    // MARK: - Kontur

    private static func drawStroke(_ path: VectorPath, style: Style, in context: CGContext) {
        guard let stroke = style.stroke, stroke.isVisible else { return }
        guard case let .solid(color) = stroke.paint else {
            // Verlaufskonturen sind laut Datenmodell erlaubt (`Stroke.paint`
            // ist ein `Paint`), aber im aktuellen Funktionsumfang taucht dafür
            // kein Werkzeug auf — statt eine ungetestete Verlaufskontur zu
            // erfinden, fällt hier nur die Vollton-Kontur tatsächlich sichtbar.
            return
        }

        context.saveGState()
        context.addPath(path.cgPath)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(stroke.width)
        context.setLineCap(cgLineCap(stroke.cap))
        context.setLineJoin(cgLineJoin(stroke.join))
        if stroke.dash.isEmpty {
            context.setLineDash(phase: 0, lengths: [])
        } else {
            context.setLineDash(phase: 0, lengths: stroke.dash)
        }
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Umsetzung Modell -> CoreGraphics

    private static func cgFillRule(_ rule: FillRule) -> CGPathFillRule {
        switch rule {
        case .nonZero: return .winding
        case .evenOdd: return .evenOdd
        }
    }

    private static func cgLineCap(_ cap: StrokeCap) -> CGLineCap {
        switch cap {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }

    private static func cgLineJoin(_ join: StrokeJoin) -> CGLineJoin {
        switch join {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}

/// Farbraum für sämtliche im Renderer erzeugten `CGColor`-Werte.
///
/// Ohne explizite Angabe legt `CGColor(red:green:blue:alpha:)` die generische
/// (nicht kalibrierte) RGB-Farbfamilie zugrunde. Zeichnet der Kontext dagegen
/// in sRGB (siehe ``RasterExporter``), rechnet CoreGraphics beim Zeichnen
/// zwischen beiden Räumen um — bei gesättigten Farben verschiebt das spürbar
/// Kanäle, die eigentlich exakt 0 bzw. 255 sein sollten. Beide Seiten auf denselben
/// Farbraum zu legen vermeidet diese Umrechnung.
private let deviceColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

private extension RGBAColor {
    var cgColor: CGColor {
        let components: [CGFloat] = [CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(alpha)]
        return CGColor(colorSpace: deviceColorSpace, components: components)
            ?? CGColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
