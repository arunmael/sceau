import CoreGraphics
import Foundation

/// Die Masse der sichtbaren Verlaufsachse.
///
/// Bewusst hier im Kern und nicht in der Ansicht: Zeichnen und Treffer­prüfung
/// müssen dieselbe Rechnung benutzen, sonst springt ein Zug woanders hin, als
/// die Marke steht. Als reiner Wert ist die Rechnung ausserdem ohne AppKit
/// prüfbar.
public struct UndoTimelineGeometry: Equatable, Sendable {

    /// Breite der Ansicht in Punkten.
    public let width: CGFloat

    /// Angewendete Schritte — der Teil links der Marke.
    public let undoDepth: Int

    /// Widerrufene Schritte — der Teil rechts der Marke.
    public let redoDepth: Int

    public init(width: CGFloat, undoDepth: Int, redoDepth: Int) {
        self.width = width
        self.undoDepth = max(0, undoDepth)
        self.redoDepth = max(0, redoDepth)
    }

    public var totalDepth: Int { undoDepth + redoDepth }

    /// Ein Punkt Rand an beiden Enden, damit die Strichenden nicht auf der
    /// Kante der Ansicht kleben und dort halb abgeschnitten werden.
    public var lineMinX: CGFloat { 1 }

    public var lineMaxX: CGFloat { max(1, width - 1) }

    /// Anteil der Achse links der Marke. Ohne Verlauf steht die Marke am Ende:
    /// Man ist auf dem aktuellen Stand, davor und danach gibt es nichts.
    public var markerFraction: CGFloat {
        totalDepth == 0 ? 1 : CGFloat(undoDepth) / CGFloat(totalDepth)
    }

    public var markerX: CGFloat {
        lineMinX + (lineMaxX - lineMinX) * markerFraction
    }

    /// Die waagerechte Position einer Rasterposition `0...totalDepth`.
    public func x(forStep step: Int) -> CGFloat {
        guard totalDepth > 0 else { return lineMaxX }
        let clamped = min(max(0, step), totalDepth)
        let fraction = CGFloat(clamped) / CGFloat(totalDepth)
        return lineMinX + (lineMaxX - lineMinX) * fraction
    }

    /// Die Umkehrung: Auf welche Verlaufstiefe zeigt diese Position?
    public func depth(atX x: CGFloat) -> Int {
        guard lineMaxX > lineMinX else { return 0 }
        let relative = min(1, max(0, (x - lineMinX) / (lineMaxX - lineMinX)))
        return Int((relative * CGFloat(totalDepth)).rounded())
    }
}

/// Entprellt einen Zug über die Verlaufsachse.
///
/// Ohne das meldete jedes Mauspixel erneut eine Zieltiefe, und ein einziges
/// Ziehen löste eine vollständige Folge von Widerrufen und Wiederholungen aus.
/// Gemeldet wird deshalb nur, wenn sich die *Rasterposition* ändert.
public struct UndoTimelinePointer: Equatable, Sendable {

    private var lastReportedDepth: Int?

    public init() {}

    /// Beginnt einen neuen Zug: Die nächste Position wird wieder gemeldet,
    /// auch wenn sie dieselbe ist wie am Ende des vorigen Zugs.
    public mutating func begin() {
        lastReportedDepth = nil
    }

    /// Die Zieltiefe an dieser Position — oder `nil`, wenn sie sich seit der
    /// letzten Meldung nicht geändert hat.
    public mutating func report(atX x: CGFloat, geometry: UndoTimelineGeometry) -> Int? {
        let target = geometry.depth(atX: x)
        guard target != lastReportedDepth else { return nil }
        lastReportedDepth = target
        return target
    }
}
