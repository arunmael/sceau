import CoreGraphics

/// Eine parametrisch beschriebene Grundform.
///
/// Grundformen bleiben absichtlich parametrisch statt sofort in Anker
/// aufgelöst — nur so bleiben Eckradius, Eckenzahl oder Zackentiefe nachträglich
/// im Inspektor änderbar ("Formen zuerst, Pfade zweitrangig"). Erst wenn eine
/// Operation es erzwingt (Zeichenstift-Bearbeitung, boolesche Verknüpfung),
/// wird die Form über ``ShapeGeometry`` in eine ``VectorPath`` überführt.
///
/// `frame` ist in allen Fällen der achsenparallele Rahmen, in den die Form
/// eingepasst wird — vor einer eventuellen Rotation des Knotens.
public enum ShapeSpec: Equatable, Sendable, Codable {
    /// Rechteck mit optional abgerundeten Ecken.
    /// `cornerRadius` wird beim Erzeugen der Geometrie auf die halbe kürzere
    /// Seite begrenzt.
    case rectangle(frame: CGRect, cornerRadius: CGFloat)

    /// Ellipse, die den Rahmen ausfüllt (bei quadratischem Rahmen ein Kreis).
    case ellipse(frame: CGRect)

    /// Regelmässiges Polygon mit `sides` Ecken (mindestens 3), einbeschrieben in
    /// den Rahmen, erste Ecke oben.
    case polygon(frame: CGRect, sides: Int)

    /// Stern mit `points` Zacken (mindestens 3). `innerRatio` (0…1) gibt an, wie
    /// weit die inneren Ecken zum Mittelpunkt rücken — kleiner Wert heisst
    /// spitzere Zacken.
    case star(frame: CGRect, points: Int, innerRatio: CGFloat)

    /// Superellipse ("Squircle"), wie sie App-Icons unter macOS/iOS verwenden —
    /// wölbt sich runder als ein abgerundetes Rechteck, aber eckiger als eine
    /// Ellipse. Fester Exponent statt eines Reglers, weil genau diese eine
    /// Silhouette der gesuchte Anwendungsfall ist ("die exakte Form einer
    /// App von Apple"), kein einstellbarer Zwischenzustand.
    case squircle(frame: CGRect)

    /// Herz, mittig im Rahmen einbeschrieben.
    case heart(frame: CGRect)

    /// Pfeil nach rechts. `shaftRatio` (0…1) gibt die Dicke des Schafts als
    /// Anteil der Rahmenhöhe an; die Pfeilspitze nimmt ein festes Drittel der
    /// Rahmenbreite ein — ein zweiter Regler dafür wäre laut Design-Prinzip 3
    /// ("wenige, aber präzise Zahlenwerte") schon zu viel für eine Vorlage.
    case arrow(frame: CGRect, shaftRatio: CGFloat)

    /// Sprechblase: abgerundetes Rechteck mit dreieckigem Schwanz unten links.
    case speechBubble(frame: CGRect, cornerRadius: CGFloat)

    /// Kreuz/Plus-Zeichen. `armRatio` (0…1) gibt die Balkendicke als Anteil
    /// der kürzeren Rahmenseite an.
    case cross(frame: CGRect, armRatio: CGFloat)

    /// Der Rahmen, in den die Form eingepasst ist.
    public var frame: CGRect {
        get {
            switch self {
            case let .rectangle(frame, _),
                 let .ellipse(frame),
                 let .polygon(frame, _),
                 let .star(frame, _, _),
                 let .squircle(frame),
                 let .heart(frame),
                 let .arrow(frame, _),
                 let .speechBubble(frame, _),
                 let .cross(frame, _):
                return frame
            }
        }
        set {
            switch self {
            case let .rectangle(_, cornerRadius):
                self = .rectangle(frame: newValue, cornerRadius: cornerRadius)
            case .ellipse:
                self = .ellipse(frame: newValue)
            case let .polygon(_, sides):
                self = .polygon(frame: newValue, sides: sides)
            case let .star(_, points, innerRatio):
                self = .star(frame: newValue, points: points, innerRatio: innerRatio)
            case .squircle:
                self = .squircle(frame: newValue)
            case .heart:
                self = .heart(frame: newValue)
            case let .arrow(_, shaftRatio):
                self = .arrow(frame: newValue, shaftRatio: shaftRatio)
            case let .speechBubble(_, cornerRadius):
                self = .speechBubble(frame: newValue, cornerRadius: cornerRadius)
            case let .cross(_, armRatio):
                self = .cross(frame: newValue, armRatio: armRatio)
            }
        }
    }

    /// Ein sprechender Vorgabename für die Ebenenliste.
    public var defaultName: String {
        switch self {
        case .rectangle: return "Rechteck"
        case .ellipse: return "Ellipse"
        case .polygon: return "Polygon"
        case .star: return "Stern"
        case .squircle: return "App-Icon-Form"
        case .heart: return "Herz"
        case .arrow: return "Pfeil"
        case .speechBubble: return "Sprechblase"
        case .cross: return "Kreuz"
        }
    }
}
