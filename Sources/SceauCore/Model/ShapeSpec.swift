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

    /// Der Rahmen, in den die Form eingepasst ist.
    public var frame: CGRect {
        get {
            switch self {
            case let .rectangle(frame, _),
                 let .ellipse(frame),
                 let .polygon(frame, _),
                 let .star(frame, _, _):
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
        }
    }
}
