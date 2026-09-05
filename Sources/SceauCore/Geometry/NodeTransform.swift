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

        case var .image(spec):
            spec.frame = spec.frame.offsetBy(dx: delta.dx, dy: delta.dy)
            result.content = .image(spec)

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

        case var .image(spec):
            let a = mirror(spec.frame.origin)
            let b = mirror(CGPoint(x: spec.frame.maxX, y: spec.frame.maxY))
            spec.frame = CGRect(from: a, to: b)
            result.content = .image(spec)

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

        case var .image(spec):
            let origin = map(spec.frame.origin)
            let corner = map(CGPoint(x: spec.frame.maxX, y: spec.frame.maxY))
            spec.frame = CGRect(
                x: min(origin.x, corner.x),
                y: min(origin.y, corner.y),
                width: abs(corner.x - origin.x),
                height: abs(corner.y - origin.y)
            )
            result.content = .image(spec)

        case let .group(children):
            result.content = .group(children: children.map { resized($0, from: source, to: target) })
        }

        return result
    }

    /// Verzieht einen Knoten frei über vier unabhängige Eckpunkte.
    ///
    /// Anders als `moved`/`mirrored`/`resized` ist eine freie Verzerrung nicht
    /// affin — für eine Einzelform oder einen Pfad gibt es danach keine
    /// sinnvolle parametrische oder rotierte Darstellung mehr, das Ergebnis
    /// wird deshalb immer ein Pfad mit Rotation 0.
    ///
    /// Bei einer **unrotierten** Gruppe bleibt die Struktur erhalten: jedes
    /// Kind wird einzeln mit demselben Rahmen/Zielviereck verzogen und behält
    /// dabei seinen eigenen Stil — sonst ginge beim Verzerren eines aus
    /// mehreren unterschiedlich gefüllten Formen bestehenden Logos die
    /// gesamte Farbgebung verloren. Bei einer **rotierten** Gruppe liesse sich
    /// das nur korrekt lösen, indem jedes Kind zuerst um das unrotierte
    /// Gruppenzentrum vorgedreht würde — dafür fehlt bislang die Grundlage;
    /// bekannte, akzeptierte Einschränkung analog zu `resized` bei rotierten
    /// Einzelobjekten. Eine rotierte Gruppe wird deshalb wie eine Einzelform
    /// behandelt: ein Pfad mit dem bisherigen Gruppenstil.
    public static func distorted(_ node: Node, from sourceRect: CGRect, to corners: QuadCorners) -> Node {
        var result = node

        if case let .group(children) = node.content, node.rotation == 0 {
            result.content = .group(children: children.map { distorted($0, from: sourceRect, to: corners) })
            return result
        }

        // Ein Bild lässt sich nicht wie eine Kontur in einzelne Anker
        // verziehen, ohne die Pixel selbst zu verzerren (das kann diese App
        // nicht) — der generische Weg unten würde `NodeGeometry.path(for:)`
        // benutzen, das für Bilder nur den rechteckigen Rahmen liefert, und
        // so das Bild durch ein leeres, kaum sichtbares Rechteck ersetzen.
        // Bewusst akzeptierte Einschränkung: nur der Rahmen wandert auf den
        // Hüllrahmen der Zielecken, das Bild selbst bleibt unverzerrt.
        if case var .image(spec) = node.content {
            let xs = [corners.topLeft.x, corners.topRight.x, corners.bottomRight.x, corners.bottomLeft.x]
            let ys = [corners.topLeft.y, corners.topRight.y, corners.bottomRight.y, corners.bottomLeft.y]
            spec.frame = CGRect(
                x: xs.min() ?? spec.frame.minX,
                y: ys.min() ?? spec.frame.minY,
                width: (xs.max() ?? spec.frame.maxX) - (xs.min() ?? spec.frame.minX),
                height: (ys.max() ?? spec.frame.maxY) - (ys.min() ?? spec.frame.minY)
            )
            result.content = .image(spec)
            return result
        }

        let resolved = NodeGeometry.path(for: node)
        result.content = .path(FreeDistortion.warped(resolved, from: sourceRect, to: corners))
        result.rotation = 0
        return result
    }
}
