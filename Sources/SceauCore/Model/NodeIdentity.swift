import CoreGraphics
import Foundation

public extension Node {

    /// Die eigene Kennung sowie die aller Nachfahren, in Zeichenreihenfolge.
    var flattenedIDs: [UUID] {
        guard let children else { return [id] }
        return [id] + children.flatMap(\.flattenedIDs)
    }

    /// Eine Kopie mit durchgehend neuen Kennungen.
    ///
    /// Die Kennungen müssen bis in die Tiefe erneuert werden: Bliebe auch nur
    /// ein Kind bei seiner alten, würden Auswahl und Undo die Kopie und das
    /// Original für dasselbe Objekt halten — ein Fehler, der erst viel später
    /// und dann sehr verwirrend auffällt.
    func duplicated() -> Node {
        var copy = self
        copy.id = UUID()
        if case let .group(children) = content {
            copy.content = .group(children: children.map { $0.duplicated() })
        }
        return copy
    }
}

public extension Document {

    /// Setzt Knoten aus der Zwischenablage ein.
    ///
    /// Sie kommen mit neuen Kennungen und leicht versetzt zuoberst an, damit
    /// eine Kopie nicht deckungsgleich hinter dem Original verschwindet.
    ///
    /// - Returns: Die Kennungen der eingesetzten Knoten, damit der Aufrufer sie
    ///   auswählen kann.
    @discardableResult
    mutating func paste(_ nodes: [Node], offsetBy offset: CGVector) -> [UUID] {
        var inserted: [UUID] = []
        for node in nodes {
            let copy = NodeTransform.moved(node.duplicated(), by: offset)
            inserted.append(copy.id)
            appendOnTop(copy)
        }
        return inserted
    }
}
