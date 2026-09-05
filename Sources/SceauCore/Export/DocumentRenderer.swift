import CoreGraphics
import Foundation
import ImageIO

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

        if case let .image(spec) = node.content {
            drawImage(spec, rotation: node.rotation, style: node.style, in: context)
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

        if let shadow = node.style.shadow {
            // Eine Transparenzebene sorgt dafür, dass der Schatten einmal
            // für die kombinierte Fläche+Kontur entsteht, statt doppelt
            // (einmal unter der Füllung, einmal unter der Kontur) — sonst
            // würde am Konturrand ein sichtbar dunklerer Saum entstehen.
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            // `setShadow` misst Versatz und Radius im unveränderlichen
            // Standard-Koordinatenraum, nicht in der aktuellen (hier bereits
            // gespiegelten) Transformationsmatrix — die vertikale Komponente
            // muss deshalb umgekehrt werden, damit ein positiver Versatz im
            // Dokument tatsächlich sichtbar nach unten zeigt.
            context.setShadow(
                offset: CGSize(width: shadow.offset.width, height: -shadow.offset.height),
                blur: shadow.blurRadius,
                color: shadow.color.cgColor
            )
        }

        drawFill(path, style: node.style, in: context)
        drawStroke(path, style: node.style, in: context)

        if node.style.shadow != nil {
            context.endTransparencyLayer()
        }

        context.restoreGState()
    }

    // MARK: - Bild

    /// Zeichnet ein eingebettetes Rasterbild in seinen Rahmen, gedreht um den
    /// Mittelpunkt des unrotierten Rahmens — dieselbe Konvention wie
    /// ``applyRotation(_:to:)`` in ``NodeGeometry`` für jede andere Kontur.
    private static func drawImage(_ spec: ImageSpec, rotation: CGFloat, style: Style, in context: CGContext) {
        guard spec.frame.width > 0, spec.frame.height > 0, spec.frame.isFiniteRect else { return }
        guard let image = decodedImage(from: spec.data) else { return }

        context.saveGState()
        context.setAlpha(style.opacity)

        if let shadow = style.shadow {
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setShadow(
                offset: CGSize(width: shadow.offset.width, height: -shadow.offset.height),
                blur: shadow.blurRadius,
                color: shadow.color.cgColor
            )
        }

        if rotation != 0 {
            let center = CGPoint(x: spec.frame.midX, y: spec.frame.midY)
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: rotation)
            context.translateBy(x: -center.x, y: -center.y)
        }
        context.draw(image, in: spec.frame)

        if style.shadow != nil {
            context.endTransparencyLayer()
        }
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

        case let .pattern(fill):
            drawPattern(fill, path: path, fillRule: style.fillRule, in: context)
        }
    }

    /// Höchstzahl an Kacheln, die für eine einzelne Füllung gezeichnet werden.
    ///
    /// Ohne Deckel könnte eine winzige `tileSize` auf einer grossen
    /// Zeichenfläche (aus einer von Hand geänderten Datei oder einfach einem
    /// zu klein eingestellten Regler) die Kachelschleife praktisch endlos
    /// laufen lassen — die App fröre ein, statt nur unschön statt korrekt
    /// gekachelt darzustellen.
    private static let maxPatternTiles = 4096

    /// Zeichnet eine Musterfüllung, indem der Kontext auf den Pfad geklippt
    /// und die Bildkachel darüber wiederholt gezeichnet wird — derselbe
    /// Klip-Ansatz wie bei ``drawGradient``, weil `CGContext` auch für
    /// Musterfüllungen keine direkte "beliebige Kontur"-API kennt.
    private static func drawPattern(
        _ fill: PatternFill,
        path: VectorPath,
        fillRule: FillRule,
        in context: CGContext
    ) {
        let bounds = path.bounds
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }
        guard fill.tileSize.width > 0, fill.tileSize.height > 0 else { return }
        guard let image = Self.decodedImage(from: fill.imageData) else { return }

        context.saveGState()
        context.addPath(path.cgPath)
        context.clip(using: cgFillRule(fillRule))

        // Im gedrehten Koordinatensystem gearbeitet, damit die Kachelung auch
        // nach einer Drehung lückenlos bleibt: Der Klip-Pfad selbst dreht sich
        // nicht mit, nur das Raster, in dem gekachelt wird.
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: fill.rotation)
        context.translateBy(x: -center.x, y: -center.y)

        // Ein Kreis um den Mittelpunkt mit Radius der Bounds-Diagonale deckt
        // die sichtbare Fläche bei jeder Drehung sicher ab.
        let diagonal = (bounds.width * bounds.width + bounds.height * bounds.height).squareRoot()
        let columns = max(1, min(Int((2 * diagonal / fill.tileSize.width).rounded(.up)), maxPatternTiles))
        let rows = max(1, min(Int((2 * diagonal / fill.tileSize.height).rounded(.up)), maxPatternTiles))
        let startX = center.x - CGFloat(columns) * fill.tileSize.width / 2
        let startY = center.y - CGFloat(rows) * fill.tileSize.height / 2

        for row in 0..<rows {
            for column in 0..<columns {
                let tileRect = CGRect(
                    x: startX + CGFloat(column) * fill.tileSize.width,
                    y: startY + CGFloat(row) * fill.tileSize.height,
                    width: fill.tileSize.width,
                    height: fill.tileSize.height
                )
                context.draw(image, in: tileRect)
            }
        }

        context.restoreGState()
    }

    /// Dekodiert Bilddaten über ImageIO statt `NSImage` — `SceauCore` bleibt
    /// dadurch frei von einer AppKit-Abhängigkeit (siehe Kopfkommentar).
    private static func decodedImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Rendert eine Musterfüllung freistehend als Bitmap in der Grösse von
    /// `bounds`, ohne auf eine Kontur geklippt zu sein.
    ///
    /// Für den Live-Canvas gedacht: `CAShapeLayer` kennt keine Musterfüllung,
    /// die Live-Darstellung maskiert deshalb — genau wie bei Verläufen — ein
    /// einfaches Bild-Layer mit der Kontur. Dieselbe Kachel-Logik wie beim
    /// Export (inklusive Deckel gegen eine ausufernde Kachelzahl) kommt so
    /// ohne Duplikation aus.
    public static func patternImage(for fill: PatternFill, bounds: CGRect) -> CGImage? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: max(1, Int(bounds.width.rounded(.up))),
            height: max(1, Int(bounds.height.rounded(.up))),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Der Rechteckpfad selbst dient nur als (nicht sichtbar wirkender)
        // "Klip" über die volle Bitmap — die eigentliche Kontur maskiert der
        // Aufrufer separat als CALayer-Maske.
        let localBounds = CGRect(origin: .zero, size: bounds.size)
        let rectPath = VectorPath(subpath: Subpath(
            anchors: [
                Anchor(corner: CGPoint(x: localBounds.minX, y: localBounds.minY)),
                Anchor(corner: CGPoint(x: localBounds.maxX, y: localBounds.minY)),
                Anchor(corner: CGPoint(x: localBounds.maxX, y: localBounds.maxY)),
                Anchor(corner: CGPoint(x: localBounds.minX, y: localBounds.maxY))
            ],
            isClosed: true
        ))
        drawPattern(fill, path: rectPath, fillRule: .nonZero, in: context)
        return context.makeImage()
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
