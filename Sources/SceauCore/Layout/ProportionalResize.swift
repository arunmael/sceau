import CoreGraphics

/// Berechnet Rahmen für Grössenänderungen mit gesperrtem Seitenverhältnis.
///
/// Die Berechnung bleibt unabhängig von Werkzeug- und Dokumentzustand, damit
/// Vorschau und endgültige Transformation dieselbe Geometrie verwenden können.
public enum ProportionalResize {

    /// Liefert den vom festen Anker aus aufgespannten proportionalen Rahmen.
    ///
    /// Die weiter gezogene Achse bestimmt die Grösse, damit der Rahmen der
    /// Mausbewegung stets vollständig folgt und nicht unerwartet schrumpft.
    /// Ein ungültiges Verhältnis fällt auf freies Ziehen zurück, weil daraus
    /// keine verlässliche proportionale Geometrie abgeleitet werden kann.
    public static func lockedRect(
        anchor: CGPoint,
        dragPoint: CGPoint,
        aspectRatio: CGFloat
    ) -> CGRect {
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return CGRect(from: anchor, to: dragPoint)
        }

        let dx = dragPoint.x - anchor.x
        let dy = dragPoint.y - anchor.y
        guard dx != 0 || dy != 0 else {
            return CGRect(origin: anchor, size: .zero)
        }

        let requestedWidth = abs(dx)
        let requestedHeight = abs(dy)
        let width: CGFloat
        let height: CGFloat

        if requestedWidth >= requestedHeight * aspectRatio {
            width = requestedWidth
            height = width / aspectRatio
        } else {
            height = requestedHeight
            width = height * aspectRatio
        }

        let oppositeCorner = CGPoint(
            x: anchor.x + (dx >= 0 ? width : -width),
            y: anchor.y + (dy >= 0 ? height : -height)
        )
        return CGRect(from: anchor, to: oppositeCorner)
    }
}
