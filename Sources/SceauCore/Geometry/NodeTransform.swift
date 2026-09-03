import CoreGraphics

/// Verschiebt und skaliert Knoten, ohne ihre Art zu verlieren.
///
/// Der springende Punkt: Eine Grundform darf beim Bewegen oder Skalieren
/// **nicht** zu einem Pfad werden — sonst wären Eckradius, Eckenzahl oder
/// Zackentiefe danach nicht mehr einstellbar. Deshalb wird bei ``ShapeSpec``
/// der Rahmen mitgeführt statt die aufgelöste Geometrie angefasst.
public enum NodeTransform {

    /// Verschiebt einen Knoten samt allen Nachfahren.
    public static func moved(_ node: Node, by delta: CGVector) -> Node {
        guard delta != CGVector(dx: 0, dy: 0) else { return node }
        var result = node

        switch node.content {
        case var .shape(spec):
            spec.frame = spec.frame.offsetBy(dx: delta.dx, dy: delta.dy)
            result.content = .shape(spec)

        case let .path(path):
            result.content = .path(path.moved(by: delta))

        case var .text(spec):
            spec.origin = CGPoint(x: spec.origin.x + delta.dx, y: spec.origin.y + delta.dy)
            result.content = .text(spec)

        case let .group(children):
            result.content = .group(children: children.map { moved($0, by: delta) })
        }

        return result
    }

    /// Spiegelt einen Knoten an der Mittelachse eines Bezugsrahmens.
    ///
    /// Für symmetrische Grundformen ändert sich dabei nur die Lage, nicht die
    /// Form selbst — gespiegelt wird deshalb der Rahmen. Bei Pfaden und Gruppen
    /// werden dagegen die Koordinaten selbst gespiegelt, denn dort ist die
    /// Asymmetrie überhaupt erst sichtbar.
    public static func mirrored(_ node: Node, along axis: Axis, about reference: CGRect) -> Node {
        guard !reference.isNull, reference.width > 0, reference.height > 0 else { return node }
        var result = node

        func mirror(_ point: CGPoint) -> CGPoint {
            switch axis {
            case .horizontal: return CGPoint(x: 2 * reference.midX - point.x, y: point.y)
            case .vertical: return CGPoint(x: point.x, y: 2 * reference.midY - point.y)
            }
        }

        switch node.content {
        case var .shape(spec):
            let a = mirror(spec.frame.origin)
            let b = mirror(CGPoint(x: spec.frame.maxX, y: spec.frame.maxY))
            spec.frame = CGRect(from: a, to: b)
            result.content = .shape(spec)

        case let .path(path):
            let transform: CGAffineTransform = switch axis {
            case .horizontal:
                CGAffineTransform(translationX: 2 * reference.midX, y: 0).scaledBy(x: -1, y: 1)
            case .vertical:
                CGAffineTransform(translationX: 0, y: 2 * reference.midY).scaledBy(x: 1, y: -1)
            }
            result.content = .path(path.applying(transform))

        case var .text(spec):
            spec.origin = mirror(spec.origin)
            result.content = .text(spec)

        case let .group(children):
            result.content = .group(children: children.map { mirrored($0, along: axis, about: reference) })
        }

        // Eine Spiegelung kehrt den Drehsinn um; sonst wanderte ein gedrehtes
        // Objekt beim Spiegeln auf die falsche Seite.
        result.rotation = -node.rotation
        return result
    }

    /// Bildet einen Knoten von einem Bezugsrahmen auf einen anderen ab.
    ///
    /// Wird beim Ziehen eines Griffs verwendet: `source` ist der Hüllrahmen zu
    /// Beginn der Zugbewegung, `target` der aktuelle. Alle ausgewählten Knoten
    /// werden über denselben Rahmen abgebildet, damit eine Mehrfachauswahl
    /// gemeinsam skaliert und ihre Anordnung zueinander behält.
    public static func resized(_ node: Node, from source: CGRect, to target: CGRect) -> Node {
        // Ein entarteter Ausgangsrahmen würde eine Division durch null ergeben;
        // dann bleibt der Knoten unverändert, statt in NaN-Koordinaten zu kippen.
        guard source.width > 0, source.height > 0,
              target.width.isFinite, target.height.isFinite
        else { return node }

        let scaleX = target.width / source.width
        let scaleY = target.height / source.height

        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: target.minX + (point.x - source.minX) * scaleX,
                y: target.minY + (point.y - source.minY) * scaleY
            )
        }

        var result = node

        switch node.content {
        case var .shape(spec):
            let origin = map(spec.frame.origin)
            let corner = map(CGPoint(x: spec.frame.maxX, y: spec.frame.maxY))
            spec.frame = CGRect(
                x: min(origin.x, corner.x),
                y: min(origin.y, corner.y),
                width: abs(corner.x - origin.x),
                height: abs(corner.y - origin.y)
            )
            // Der Eckradius muss mitskalieren, sonst wirkt eine stark
            // vergrösserte Form plötzlich fast eckig.
            if case let .rectangle(frame, radius) = spec {
                spec = .rectangle(frame: frame, cornerRadius: radius * min(abs(scaleX), abs(scaleY)))
            }
            result.content = .shape(spec)

        case let .path(path):
            let transform = CGAffineTransform(translationX: target.minX, y: target.minY)
                .scaledBy(x: scaleX, y: scaleY)
                .translatedBy(x: -source.minX, y: -source.minY)
            result.content = .path(path.applying(transform))

        case var .text(spec):
            spec.origin = map(spec.origin)
            // Schriftgrösse folgt der Höhe — eine Schrift getrennt in Breite und
            // Höhe zu verzerren, gehört nicht zum Funktionsumfang.
            spec.fontSize *= abs(scaleY)
            result.content = .text(spec)

        case let .group(children):
            result.content = .group(children: children.map { resized($0, from: source, to: target) })
        }

        return result
    }
}
