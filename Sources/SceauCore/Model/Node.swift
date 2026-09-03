import CoreGraphics
import Foundation

/// Ein Element des Dokumentbaums — Grundform, freier Pfad, Text oder Gruppe.
///
/// Bewusst ein Werttyp statt einer Klassenhierarchie: dadurch ist der ganze
/// Baum `Codable`, `Sendable` und vor allem billig zu kopieren, was Undo/Redo
/// über Schnappschüsse erst praktikabel macht.
///
/// ## Warum keine allgemeine Transformationsmatrix
/// Knoten tragen nur einen Rotationswinkel, keine freie `CGAffineTransform`.
/// Verschieben und Skalieren wird stattdessen direkt in die Geometrie
/// geschrieben (Rahmen einer Grundform bzw. Ankerkoordinaten eines Pfades).
/// Das erspart die gesamte Klasse von Fehlern, die aus verschachtelten,
/// zusammengesetzten Transformationen entsteht, und Scherung braucht eine
/// Logo-App nicht.
public struct Node: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var isVisible: Bool
    public var isLocked: Bool
    /// Drehung im Bogenmass um den Mittelpunkt des eigenen Hüllrahmens.
    public var rotation: CGFloat
    public var style: Style
    public var content: Content

    /// Die eigentliche Nutzlast eines Knotens.
    public enum Content: Equatable, Sendable, Codable {
        /// Parametrische Grundform — bleibt im Inspektor nachjustierbar.
        case shape(ShapeSpec)
        /// Freier Pfad aus Ankerpunkten, etwa vom Zeichenstift oder als
        /// Ergebnis einer booleschen Operation.
        case path(VectorPath)
        case text(TextSpec)
        /// Gruppe. `children` folgt derselben Z-Reihenfolge wie
        /// ``Document/nodes``: Index 0 liegt zuunterst.
        case group(children: [Node])
    }

    public init(
        id: UUID = UUID(),
        name: String,
        isVisible: Bool = true,
        isLocked: Bool = false,
        rotation: CGFloat = 0,
        style: Style = Style(),
        content: Content
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.rotation = rotation
        self.style = style
        self.content = content
    }

    /// Erzeugt einen Knoten für eine Grundform mit passendem Vorgabenamen.
    public init(shape: ShapeSpec, style: Style = Style()) {
        self.init(name: shape.defaultName, style: style, content: .shape(shape))
    }

    /// Die Kinder, falls dieser Knoten eine Gruppe ist.
    public var children: [Node]? {
        if case let .group(children) = content { return children }
        return nil
    }

    public var isGroup: Bool { children != nil }
}
