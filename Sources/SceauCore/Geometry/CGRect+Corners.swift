import CoreGraphics

public extension CGRect {
    /// Das Rechteck zwischen zwei beliebigen Eckpunkten.
    ///
    /// Nimmt die Punkte in beliebiger Lage zueinander entgegen und normalisiert
    /// selbst — nötig überall dort, wo ein Rahmen aus einer Zugbewegung oder
    /// einer Spiegelung entsteht und die „obere linke" Ecke nicht mehr
    /// zwingend oben links liegt.
    init(from: CGPoint, to: CGPoint) {
        self.init(
            x: Swift.min(from.x, to.x),
            y: Swift.min(from.y, to.y),
            width: Swift.abs(to.x - from.x),
            height: Swift.abs(to.y - from.y)
        )
    }
}
