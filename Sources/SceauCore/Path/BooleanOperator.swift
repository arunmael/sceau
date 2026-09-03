import CoreGraphics
import iOverlay

/// Die vier Pathfinder-Operationen, die laut Entwicklungsplan (Abschnitt 5.3)
/// wirklich gebraucht werden — bewusst kein vollständiges Pathfinder-Panel.
public enum BooleanOperation: String, Sendable, CaseIterable {
    case union, subtract, intersect, exclude
}

/// Fehler einer booleschen Operation.
///
/// Ein leeres Ergebnis wird bewusst **nicht** als leerer `VectorPath`
/// zurückgegeben, sondern als Fehler geworfen — sonst übersieht der Aufrufer
/// leicht, dass z. B. eine Schnittmenge ohne Überlappung keine Fläche ergibt.
public enum BooleanError: Error, Equatable {
    /// Eine der beiden Eingaben enthält keine gültige Fläche (kein Anker,
    /// oder alle Teilpfade mit weniger als drei Punkten nach dem Abflachen).
    case emptyInput
    /// Die Operation ergibt keine Fläche, z. B. eine Schnittmenge zweier
    /// Formen, die sich nicht überlappen.
    case emptyResult
}

/// Boolesche Operationen auf ``VectorPath``, angebunden an `iOverlay`.
///
/// `iOverlay` rechnet auf Polygonen, nicht auf Bézierkurven — Kurven werden
/// deshalb vor der Operation mit ``Flattener`` abgeflacht. Das Ergebnis bleibt
/// bewusst ein Polyzug (kein Zurückfitten von Kurven, siehe ``Flattener``).
public enum BooleanOperator {

    /// Führt eine boolesche Operation zwischen `subject` und `clip` aus.
    ///
    /// - Parameter tolerance: Abflach-Toleranz vor der Operation, siehe
    ///   ``Flattener/defaultTolerance``. Feiner = genauer, aber mehr Punkte.
    public static func apply(
        _ operation: BooleanOperation,
        subject: VectorPath,
        clip: VectorPath,
        tolerance: CGFloat = Flattener.defaultTolerance
    ) throws -> VectorPath {
        let subjectPolygons = Flattener.polygons(of: subject, tolerance: tolerance)
        let clipPolygons = Flattener.polygons(of: clip, tolerance: tolerance)

        guard !subjectPolygons.isEmpty, !clipPolygons.isEmpty else {
            throw BooleanError.emptyInput
        }

        let overlay = CGOverlay(subjectPaths: subjectPolygons, clipPaths: clipPolygons)
        let graph = overlay.buildGraph(fillRule: .nonZero)
        let shapes = graph.extractShapes(overlayRule: overlayRule(for: operation), minArea: 0)

        // Jede Form liefert einen Ring pro Kontur: der erste ist die
        // Aussenkontur (im Uhrzeigersinn), alle weiteren sind Löcher (gegen
        // den Uhrzeigersinn). Alle landen als eigene, geschlossene Subpaths im
        // selben VectorPath — die Füllregel `nonZero` sorgt zusammen mit der
        // von iOverlay gelieferten Umlaufrichtung dafür, dass Löcher Löcher
        // bleiben. Die Umlaufrichtung wird unverändert übernommen.
        var subpaths: [Subpath] = []
        for shape in shapes {
            for ring in shape where ring.count >= 3 {
                subpaths.append(Subpath(closedPolygon: ring))
            }
        }

        guard !subpaths.isEmpty else {
            throw BooleanError.emptyResult
        }

        return VectorPath(subpaths: subpaths)
    }

    private static func overlayRule(for operation: BooleanOperation) -> OverlayRule {
        switch operation {
        case .union: return .union
        case .subtract: return .difference
        case .intersect: return .intersect
        case .exclude: return .xor
        }
    }
}
