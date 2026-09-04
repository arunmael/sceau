import AppKit
import SceauCore

extension RGBAColor {
    /// `CGColor` im sRGB-Raum — die Farbräume werden hier bewusst explizit
    /// festgelegt, damit exportierte und angezeigte Farben übereinstimmen.
    var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            components: [CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(alpha)]
        ) ?? CGColor(gray: 0, alpha: CGFloat(alpha))
    }
}

/// Baut aus dem Dokumentmodell den Ebenenbaum aus `CALayer`n.
///
/// `CAShapeLayer` ist auf macOS der natürliche Weg für Vektorformen: von der
/// GPU zusammengesetzt und direkt mit Fläche, Kontur und Strichmuster
/// kompatibel.
///
/// ## Warum der Baum komplett neu gebaut wird
/// Bei jeder Änderung entsteht der Ebenenbaum neu, statt ihn abzugleichen.
/// Ein Abgleich zwischen Modell und Ebenenbaum ist eine klassische Quelle für
/// Zustandsfehler, und bei der Dokumentgrösse, für die diese App gedacht ist
/// (Logos und Icons, also Dutzende statt Tausende Objekte), ist der Neubau
/// ohnehin nicht messbar. Implizite Animationen werden dabei abgeschaltet,
/// sonst würde jede Änderung nachwabern.
enum CanvasRenderer {

    /// Erzeugt die Ebene für einen Knoten, oder `nil`, wenn er nichts sichtbar
    /// beiträgt.
    static func makeLayer(for node: Node) -> CALayer? {
        guard node.isVisible, node.style.opacity > 0 else { return nil }

        if case let .group(children) = node.content {
            let container = CALayer()
            container.opacity = Float(node.style.opacity)
            for child in children {
                if let childLayer = makeLayer(for: child) {
                    container.addSublayer(childLayer)
                }
            }
            return container.sublayers?.isEmpty == false ? container : nil
        }

        let path = NodeGeometry.path(for: node)
        guard !path.isEmpty else { return nil }
        let cgPath = path.cgPath

        let container = CALayer()
        container.opacity = Float(node.style.opacity)

        if let fillLayer = makeFillLayer(path: cgPath, paint: node.style.fill, style: node.style) {
            container.addSublayer(fillLayer)
        }
        if let stroke = node.style.stroke, stroke.isVisible,
           let strokeLayer = makeStrokeLayer(path: cgPath, stroke: stroke) {
            container.addSublayer(strokeLayer)
        }

        return container.sublayers?.isEmpty == false ? container : nil
    }

    // MARK: - Fläche

    private static func makeFillLayer(path: CGPath, paint: Paint, style: Style) -> CALayer? {
        switch paint {
        case .none:
            return nil

        case let .solid(color):
            let shape = CAShapeLayer()
            shape.path = path
            shape.fillColor = color.cgColor
            shape.fillRule = style.fillRule == .evenOdd ? .evenOdd : .nonZero
            shape.strokeColor = nil
            return shape

        case let .linearGradient(gradient), let .radialGradient(gradient):
            // `CAShapeLayer` kann selbst keinen Verlauf füllen. Der übliche Weg
            // ist deshalb ein Verlaufs-Layer, das von der Form maskiert wird.
            let mask = CAShapeLayer()
            mask.path = path
            mask.fillColor = NSColor.black.cgColor
            mask.fillRule = style.fillRule == .evenOdd ? .evenOdd : .nonZero

            let isRadial: Bool = if case .radialGradient = paint { true } else { false }
            let gradientLayer = makeGradientLayer(gradient, radial: isRadial)
            gradientLayer.frame = path.boundingBoxOfPath
            // Die Maske arbeitet im Koordinatensystem des maskierten Layers,
            // das am Hüllrahmen ausgerichtet ist — daher der Versatz.
            mask.frame = CGRect(origin: .zero, size: gradientLayer.frame.size)
            var shift = CGAffineTransform(
                translationX: -gradientLayer.frame.minX,
                y: -gradientLayer.frame.minY
            )
            mask.path = path.copy(using: &shift)
            gradientLayer.mask = mask
            return gradientLayer
        }
    }

    // MARK: - Kontur

    private static func makeStrokeLayer(path: CGPath, stroke: Stroke) -> CALayer? {
        let shape = CAShapeLayer()
        shape.path = path
        shape.fillColor = nil
        shape.lineWidth = stroke.width
        shape.lineCap = stroke.cap.caCap
        shape.lineJoin = stroke.join.caJoin
        shape.lineDashPattern = stroke.dash.isEmpty ? nil : stroke.dash.map { NSNumber(value: Double($0)) }

        switch stroke.paint {
        case .none:
            return nil
        case let .solid(color):
            shape.strokeColor = color.cgColor
            return shape
        case let .linearGradient(gradient), let .radialGradient(gradient):
            let isRadial: Bool = if case .radialGradient = stroke.paint { true } else { false }
            shape.strokeColor = NSColor.black.cgColor
            let gradientLayer = makeGradientLayer(gradient, radial: isRadial)
            // Kontur kann über den Pfad hinausragen, daher der aufgeweitete Rahmen.
            let box = path.boundingBoxOfPath.insetBy(dx: -stroke.width, dy: -stroke.width)
            gradientLayer.frame = box
            shape.frame = CGRect(origin: .zero, size: box.size)
            var shift = CGAffineTransform(translationX: -box.minX, y: -box.minY)
            shape.path = path.copy(using: &shift)
            gradientLayer.mask = shape
            return gradientLayer
        }
    }

    private static func makeGradientLayer(_ gradient: Gradient, radial: Bool) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.type = radial ? .radial : .axial
        let sorted = gradient.stops.sorted { $0.location < $1.location }
        layer.colors = sorted.map { $0.color.cgColor }
        layer.locations = sorted.map { NSNumber(value: Double($0.location)) }
        layer.startPoint = gradient.start
        layer.endPoint = gradient.end
        return layer
    }
}

private extension StrokeCap {
    var caCap: CAShapeLayerLineCap {
        switch self {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }
}

private extension StrokeJoin {
    var caJoin: CAShapeLayerLineJoin {
        switch self {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}
