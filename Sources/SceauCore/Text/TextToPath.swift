import CoreGraphics
import CoreText
import Foundation

/// Wandelt eine Textebene in editierbare Vektorkonturen um.
///
/// Grundlage des Exports: nur so bleibt ein Logo unabhängig davon, ob die
/// verwendete Schrift beim Empfänger installiert ist. `CoreText` liefert
/// Glyphenpfade im typografischen Koordinatensystem (Ursprung auf der
/// Grundlinie, y wächst nach oben), während das Dokumentmodell dieser App den
/// Ursprung links oben hat und y nach unten zählt. Jeder Glyphenpfad wird
/// deshalb an der Grundlinie gespiegelt — Oberlängen landen dadurch bei
/// kleinerem y als `spec.origin.y`, also oberhalb der Grundlinie im
/// Dokumentkoordinatensystem.
public enum TextToPath {

    /// Wandelt eine Textebene in Konturen um — je Glyph ein oder mehrere Teilpfade.
    public static func path(for spec: TextSpec) -> VectorPath {
        guard !spec.string.isEmpty else { return VectorPath() }

        let font = CTFontCreateWithName(spec.fontName as CFString, spec.fontSize, nil)
        let layout = glyphLayout(for: spec, font: font)

        var resultSubpaths: [Subpath] = []
        for entry in layout.glyphs {
            // Spiegelung an der Grundlinie (y → −y) plus Verschiebung an die
            // laufende Schreibposition, in einem Schritt: ein Glyph-Punkt
            // (gx, gy) landet bei (gx + origin.x + penPosition, origin.y − gy).
            // Die Übergabe an CTFontCreatePathForGlyph ist sauberer als eine
            // nachträgliche Transformation des fertigen Pfades.
            var transform = CGAffineTransform(
                a: 1, b: 0, c: 0, d: -1,
                tx: spec.origin.x + entry.penPosition, ty: spec.origin.y
            )

            guard let cgPath = CTFontCreatePathForGlyph(font, entry.glyph, &transform) else {
                continue
            }
            resultSubpaths.append(contentsOf: subpaths(from: cgPath))
        }

        return VectorPath(subpaths: resultSubpaths)
    }

    /// Der Vorschub des gesetzten Textes, ohne ihn in Pfade umzuwandeln.
    public static func advance(for spec: TextSpec) -> CGFloat {
        guard !spec.string.isEmpty else { return 0 }
        let font = CTFontCreateWithName(spec.fontName as CFString, spec.fontSize, nil)
        return glyphLayout(for: spec, font: font).totalAdvance
    }

    // MARK: - Layout

    private struct GlyphEntry {
        let glyph: CGGlyph
        /// Position der Schreibmarke (relativ zu `origin.x`), an der dieser
        /// Glyph beginnt.
        let penPosition: CGFloat
    }

    private struct GlyphLayout {
        let glyphs: [GlyphEntry]
        let totalAdvance: CGFloat
    }

    /// Berechnet Glyphen und Schreibpositionen für die gesamte Zeichenkette.
    ///
    /// Zeichen ohne Glyph in der Schrift (Glyph 0, z. B. nicht darstellbare
    /// Codepoints) werden übersprungen, tragen aber weiterhin ihren Vorschub
    /// bei, damit nachfolgende Zeichen nicht verrutschen.
    private static func glyphLayout(for spec: TextSpec, font: CTFont) -> GlyphLayout {
        let utf16 = Array(spec.string.utf16)
        guard !utf16.isEmpty else { return GlyphLayout(glyphs: [], totalAdvance: 0) }

        // CTFontGetGlyphsForCharacters liefert `false`, sobald mindestens ein
        // Zeichen keinen Glyph hat — die Advances der übrigen Zeichen bleiben
        // trotzdem gültig und werden weiter erhoben, Zeichen ohne Glyph
        // (Glyph 0) tragen später nur ihren Vorschub bei, ohne einen Pfad zu
        // erzeugen. `utf16` ist hier nicht leer (siehe guard oben), die
        // Pufferzugriffe unten liefern deshalb stets gültige Adressen.
        var cgGlyphs = [CGGlyph](repeating: 0, count: utf16.count)
        utf16.withUnsafeBufferPointer { chars in
            cgGlyphs.withUnsafeMutableBufferPointer { glyphs in
                guard let charsBase = chars.baseAddress, let glyphsBase = glyphs.baseAddress else { return }
                _ = CTFontGetGlyphsForCharacters(font, charsBase, glyphsBase, utf16.count)
            }
        }

        var advances = [CGSize](repeating: .zero, count: utf16.count)
        cgGlyphs.withUnsafeBufferPointer { glyphs in
            advances.withUnsafeMutableBufferPointer { adv in
                guard let glyphsBase = glyphs.baseAddress, let advBase = adv.baseAddress else { return }
                CTFontGetAdvancesForGlyphs(font, .horizontal, glyphsBase, advBase, utf16.count)
            }
        }

        var entries: [GlyphEntry] = []
        var pen: CGFloat = 0

        for (index, glyph) in cgGlyphs.enumerated() {
            if glyph != 0 {
                entries.append(GlyphEntry(glyph: glyph, penPosition: pen))
            }
            pen += advances[index].width
            pen += spec.tracking
            if isWhitespaceUTF16Unit(utf16[index]) {
                pen += spec.wordSpacing
            }
        }

        return GlyphLayout(glyphs: entries, totalAdvance: pen)
    }

    private static func isWhitespaceUTF16Unit(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return Character(scalar).isWhitespace
    }

    // MARK: - CGPath → VectorPath

    /// Überführt einen `CGPath` (typischerweise ein einzelner Glyph, ggf. mit
    /// Löchern wie beim „O") in seine `Subpath`-Repräsentation.
    private static func subpaths(from cgPath: CGPath) -> [Subpath] {
        var result: [Subpath] = []
        var currentAnchors: [Anchor] = []
        var currentStart: CGPoint = .zero
        var currentPoint: CGPoint = .zero

        func flushOpenSubpath() {
            if !currentAnchors.isEmpty {
                result.append(Subpath(anchors: currentAnchors, isClosed: false))
            }
            currentAnchors = []
        }

        cgPath.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                flushOpenSubpath()
                let point = element.points[0]
                currentAnchors = [Anchor(corner: point)]
                currentStart = point
                currentPoint = point

            case .addLineToPoint:
                let point = element.points[0]
                currentAnchors.append(Anchor(corner: point))
                currentPoint = point

            case .addQuadCurveToPoint:
                // Quadratisch → kubisch: c1 = p0 + 2/3(q − p0), c2 = p2 + 2/3(q − p2).
                let q = element.points[0]
                let p2 = element.points[1]
                let p0 = currentPoint
                let c1 = CGPoint(x: p0.x + (2.0 / 3.0) * (q.x - p0.x), y: p0.y + (2.0 / 3.0) * (q.y - p0.y))
                let c2 = CGPoint(x: p2.x + (2.0 / 3.0) * (q.x - p2.x), y: p2.y + (2.0 / 3.0) * (q.y - p2.y))
                appendCubic(control1: c1, control2: c2, end: p2, to: &currentAnchors)
                currentPoint = p2

            case .addCurveToPoint:
                let c1 = element.points[0]
                let c2 = element.points[1]
                let end = element.points[2]
                appendCubic(control1: c1, control2: c2, end: end, to: &currentAnchors)
                currentPoint = end

            case .closeSubpath:
                if !currentAnchors.isEmpty {
                    result.append(Subpath(anchors: currentAnchors, isClosed: true))
                }
                currentAnchors = []
                currentPoint = currentStart

            @unknown default:
                break
            }
        }

        flushOpenSubpath()
        return result
    }

    /// Hängt einen kubischen Bogen an: der ausgehende Griff (`controlOut`)
    /// gehört an den bisherigen letzten Anker, der eingehende Griff
    /// (`controlIn`) an den neuen Anker am Kurvenende.
    private static func appendCubic(control1: CGPoint, control2: CGPoint, end: CGPoint, to anchors: inout [Anchor]) {
        guard var last = anchors.last else {
            // Sollte bei CoreText-Pfaden nicht vorkommen (jede Kurve folgt auf
            // ein moveTo), aber ohne vorherigen Anker gibt es keinen Ort für
            // den ausgehenden Griff — dann degeneriert das Segment zur Geraden.
            anchors.append(Anchor(corner: end))
            return
        }
        last.controlOut = control1
        anchors[anchors.count - 1] = last
        anchors.append(Anchor(point: end, controlIn: control2, controlOut: end))
    }
}
