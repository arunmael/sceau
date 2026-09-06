import CoreGraphics

/// Eimer-/Flächenfüller: findet die Fläche, die von überlappenden Konturen
/// unmittelbar um einen Klickpunkt eingeschlossen wird — wie das
/// „Live Paint"-Werkzeug in Vektorprogrammen.
///
/// Bewusst **kein** pixelbasiertes Flood-Fill (das wäre für ein Vektorprogramm
/// der falsche Ansatz und würde beim Export wieder zu Rasterdaten führen).
/// Stattdessen eine rein geometrische Definition, die die vorhandene
/// Boolesche-Operationen-Maschinerie (``BooleanOperator``) wiederverwendet:
///
/// Die eingeschlossene Fläche ist die Schnittmenge aller Konturen, die den
/// Punkt enthalten, abzüglich aller Konturen, die ihn nicht enthalten, aber
/// mit dieser Schnittmenge überlappen. Bei nur einer Kontur ist das schlicht
/// die Kontur selbst.
public enum BucketFill {

    /// Eine Kandidatenkontur mit ihrer eigenen Füllregel — dieselbe
    /// Kombination aus Pfad und Regel, die auch beim Treffertest verwendet
    /// wird (siehe `CanvasView.hits(node:point:)`).
    public struct Boundary {
        public var path: VectorPath
        public var fillRule: CGPathFillRule

        public init(path: VectorPath, fillRule: CGPathFillRule) {
            self.path = path
            self.fillRule = fillRule
        }
    }

    public enum Error: Swift.Error, Equatable {
        /// Keine der Konturen umschliesst den Punkt — es gibt nichts zu füllen.
        case noEnclosingBoundary
    }

    /// Berechnet die eingeschlossene Fläche um `point`.
    ///
    /// - Parameter boundaries: Alle in Frage kommenden Konturen, üblicherweise
    ///   die Umrisse aller sichtbaren, entsperrten Knoten des Dokuments.
    public static func region(
        at point: CGPoint,
        boundaries: [Boundary],
        tolerance: CGFloat = Flattener.defaultTolerance
    ) throws -> VectorPath {
        let usable = boundaries.filter { !$0.path.isEmpty }
        let containing = usable.filter { $0.path.cgPath.contains(point, using: $0.fillRule) }

        guard let first = containing.first else {
            throw Error.noEnclosingBoundary
        }

        do {
            var cell = first.path
            for boundary in containing.dropFirst() {
                cell = try BooleanOperator.apply(.intersect, subject: cell, clip: boundary.path, tolerance: tolerance)
            }

            let notContaining = usable.filter { !$0.path.cgPath.contains(point, using: $0.fillRule) }
            for boundary in notContaining {
                // Kein Überlapp mit der bisherigen Zelle: nichts abzuschneiden.
                // Ein Aufruf würde hier nur unnötig mit `.emptyInput` scheitern.
                guard cell.bounds.intersects(boundary.path.bounds) else { continue }
                cell = try BooleanOperator.apply(.subtract, subject: cell, clip: boundary.path, tolerance: tolerance)
            }

            return cell
        } catch is BooleanError {
            // Sowohl eine leere Schnittmenge (die enthaltenden Konturen
            // berühren sich am Punkt nur zufällig) als auch ein durch Abzug
            // vollständig verschluckter Rest laufen auf dasselbe hinaus: an
            // dieser Stelle bleibt keine Fläche zum Füllen übrig.
            throw Error.noEnclosingBoundary
        }
    }
}
