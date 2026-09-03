import Foundation

/// Rekursive Operationen auf dem Dokumentbaum.
///
/// `Document.nodes` ist nur die oberste Ebene — Gruppen tragen ihre Kinder in
/// `Node.Content.group`. Jede Operation hier muss deshalb selbst in die Tiefe
/// steigen; es gibt keine flache Zwischenrepräsentation, die synchron zu
/// halten wäre (das wäre eine zusätzliche Fehlerquelle für wenig Nutzen bei
/// den Baumgrössen, die eine Logo-App erwarten muss).
public extension Document {
    /// Findet einen Knoten beliebiger Tiefe.
    func node(id: UUID) -> Node? {
        Document.findNode(id: id, in: nodes)
    }

    private static func findNode(id: UUID, in level: [Node]) -> Node? {
        for candidate in level {
            if candidate.id == id { return candidate }
            if case let .group(children) = candidate.content,
               let found = findNode(id: id, in: children) {
                return found
            }
        }
        return nil
    }

    /// Der Index eines Knotens innerhalb seiner eigenen Ebene — also im
    /// Dokument oder in der Gruppe, zu der er gehört.
    func indexInParent(of id: UUID) -> Int? {
        Document.indexInParent(of: id, in: nodes)
    }

    private static func indexInParent(of id: UUID, in level: [Node]) -> Int? {
        if let index = level.firstIndex(where: { $0.id == id }) {
            return index
        }
        for candidate in level {
            if case let .group(children) = candidate.content,
               let index = indexInParent(of: id, in: children) {
                return index
            }
        }
        return nil
    }

    /// Ersetzt einen Knoten beliebiger Tiefe an Ort und Stelle. Tut nichts, wenn es ihn nicht gibt.
    mutating func replace(_ node: Node) {
        nodes = Document.replacing(node, in: nodes)
    }

    private static func replacing(_ node: Node, in level: [Node]) -> [Node] {
        level.map { candidate in
            if candidate.id == node.id { return node }
            if case let .group(children) = candidate.content {
                var updated = candidate
                updated.content = .group(children: replacing(node, in: children))
                return updated
            }
            return candidate
        }
    }

    /// Entfernt Knoten beliebiger Tiefe. Entfernt ein Elternteil, werden dessen Kinder mitentfernt,
    /// weil sie schlicht Teil des entfernten Teilbaums sind.
    mutating func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        nodes = Document.removing(ids: ids, from: nodes)
    }

    private static func removing(ids: Set<UUID>, from level: [Node]) -> [Node] {
        level.compactMap { candidate -> Node? in
            if ids.contains(candidate.id) { return nil }
            if case let .group(children) = candidate.content {
                var updated = candidate
                updated.content = .group(children: removing(ids: ids, from: children))
                return updated
            }
            return candidate
        }
    }

    /// Fügt oben auf (ans Ende von `nodes`, also zuoberst in der Z-Reihenfolge) ein.
    mutating func appendOnTop(_ node: Node) {
        nodes.append(node)
    }

    /// Alle Knoten in Zeichenreihenfolge, flach ausgerollt (Gruppen samt Kindern).
    ///
    /// Eine Gruppe erscheint selbst als Eintrag, unmittelbar gefolgt von ihren
    /// Kindern — praktisch für Trefferlisten (Rubber-Band-Auswahl, Ebenen-Suche),
    /// die nicht zwischen Gruppe und Inhalt unterscheiden müssen.
    var flattenedNodes: [Node] {
        Document.flatten(nodes)
    }

    /// Die Knoten zu den angegebenen Kennungen, beliebig tief und in
    /// Zeichenreihenfolge. Unbekannte Kennungen werden übergangen.
    func nodes(with ids: Set<UUID>) -> [Node] {
        flattenedNodes.filter { ids.contains($0.id) }
    }

    private static func flatten(_ level: [Node]) -> [Node] {
        level.flatMap { node -> [Node] in
            if case let .group(children) = node.content {
                return [node] + flatten(children)
            }
            return [node]
        }
    }

    /// Der Pfad von der Wurzel zu einem Knoten (dessen Vorfahren, äusserster zuerst).
    /// Liegt der Knoten auf der Wurzelebene oder existiert er nicht, ist das Ergebnis leer.
    func ancestors(of id: UUID) -> [Node] {
        Document.ancestorChain(of: id, in: nodes, trail: []) ?? []
    }

    private static func ancestorChain(of id: UUID, in level: [Node], trail: [Node]) -> [Node]? {
        for candidate in level {
            if candidate.id == id { return trail }
            if case let .group(children) = candidate.content,
               let found = ancestorChain(of: id, in: children, trail: trail + [candidate]) {
                return found
            }
        }
        return nil
    }
}

public extension Document {
    /// Referenz auf die Ebene, in der ein Knoten liegt — die Wurzel oder eine
    /// bestimmte Gruppe. Ein eigener Typ statt `UUID?`, weil ein optionaler
    /// Dictionary-Schlüssel (`[UUID?: Int]`) beim Zählen der Häufigkeiten in
    /// unangenehm doppelt-optionale Ausdrücke abrutscht.
    private enum ParentLevel: Hashable {
        case root
        case group(UUID)
    }

    /// Fasst die angegebenen Knoten zu einer neuen Gruppe zusammen.
    ///
    /// Die Gruppe landet an der Position des **obersten** beteiligten Knotens.
    /// Die Z-Reihenfolge der Mitglieder untereinander bleibt erhalten.
    /// Gibt die ID der neuen Gruppe zurück, oder nil, wenn weniger als zwei
    /// gruppierbare Knoten übrig bleiben.
    mutating func group(ids: Set<UUID>, name: String) -> UUID? {
        guard !ids.isEmpty else { return nil }

        // Eine Mehrfachauswahl kann über Ebenen hinweg reichen (z.B. eine
        // Rahmenauswahl im Canvas, die eine Gruppe und einen Wurzelknoten
        // überlappt). Gruppieren ergibt aber nur innerhalb einer Ebene Sinn —
        // Kinder aus verschiedenen Koordinatenkontexten in eine Gruppe zu
        // stecken würde ihre Position relativ zueinander verfälschen. Wir
        // gruppieren daher nur den Teil der Auswahl, der sich das häufigste
        // gemeinsame Elternteil teilt, und lassen den Rest unangetastet. Bei
        // Gleichstand gewinnt die Wurzel, weil eine gewöhnliche Mehrfachauswahl
        // im Canvas meist genau dort ansetzt.
        var parentOf: [UUID: ParentLevel] = [:]
        for id in ids {
            guard node(id: id) != nil else { continue }
            let ancestry = ancestors(of: id)
            parentOf[id] = ancestry.last.map { .group($0.id) } ?? .root
        }
        guard !parentOf.isEmpty else { return nil }

        var counts: [ParentLevel: Int] = [:]
        for level in parentOf.values {
            counts[level, default: 0] += 1
        }
        let chosenLevel = counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key != .root && rhs.key == .root
        }?.key ?? .root

        let members = Set(parentOf.filter { $0.value == chosenLevel }.keys)
        guard members.count >= 2 else { return nil }

        switch chosenLevel {
        case .root:
            guard let (newNodes, newGroup) = Document.grouped(members: members, name: name, in: nodes) else {
                return nil
            }
            nodes = newNodes
            return newGroup.id

        case let .group(parentID):
            guard let parentNode = node(id: parentID), case let .group(children) = parentNode.content else {
                return nil
            }
            guard let (newChildren, newGroup) = Document.grouped(members: members, name: name, in: children) else {
                return nil
            }
            var updatedParent = parentNode
            updatedParent.content = .group(children: newChildren)
            replace(updatedParent)
            return newGroup.id
        }
    }

    /// Baut die neue Gruppe und die daraus resultierende Knotenliste einer einzelnen Ebene.
    private static func grouped(members: Set<UUID>, name: String, in level: [Node]) -> ([Node], Node)? {
        let memberIndices = level.indices.filter { members.contains(level[$0].id) }
        guard memberIndices.count >= 2 else { return nil }

        let memberNodes = memberIndices.map { level[$0] } // in ihrer bisherigen Z-Reihenfolge
        let topIndex = memberIndices.max()!
        let newGroup = Node(name: name, content: .group(children: memberNodes))

        var result = level
        for index in memberIndices.sorted(by: >) {
            result.remove(at: index)
        }
        // Die Einfügeposition folgt dem obersten Mitglied, korrigiert um die
        // Mitglieder, die unterhalb von ihm herausgenommen wurden und die
        // verbleibenden Knoten dadurch nach unten rücken liessen.
        let removedBelowTop = memberIndices.filter { $0 < topIndex }.count
        let insertIndex = topIndex - removedBelowTop
        result.insert(newGroup, at: insertIndex)
        return (result, newGroup)
    }

    /// Löst Gruppen auf und setzt ihre Kinder an die Stelle der Gruppe.
    /// Gibt die IDs der freigelegten Kinder zurück.
    @discardableResult
    mutating func ungroup(ids: Set<UUID>) -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        var exposed: Set<UUID> = []
        nodes = Document.ungrouped(ids: ids, in: nodes, exposed: &exposed)
        return exposed
    }

    private static func ungrouped(ids: Set<UUID>, in level: [Node], exposed: inout Set<UUID>) -> [Node] {
        var result: [Node] = []
        result.reserveCapacity(level.count)
        for candidate in level {
            if ids.contains(candidate.id), case let .group(children) = candidate.content {
                for child in children { exposed.insert(child.id) }
                result.append(contentsOf: children)
            } else if case let .group(children) = candidate.content {
                var updated = candidate
                updated.content = .group(children: ungrouped(ids: ids, in: children, exposed: &exposed))
                result.append(updated)
            } else {
                result.append(candidate)
            }
        }
        return result
    }

    /// Verschiebt Knoten in der Z-Reihenfolge ihrer jeweiligen Ebene.
    /// Ein Index ausserhalb des gültigen Bereichs wird geklemmt statt abzulehnen —
    /// "ganz nach oben/unten" ist eine gängige Geste (z.B. Tastaturkürzel), die
    /// nicht am exakten Index scheitern soll.
    mutating func reorder(id: UUID, to index: Int) {
        guard node(id: id) != nil else { return }
        let parentID = ancestors(of: id).last?.id

        guard let parentID else {
            guard let currentIndex = nodes.firstIndex(where: { $0.id == id }) else { return }
            var updated = nodes
            let moved = updated.remove(at: currentIndex)
            updated.insert(moved, at: min(max(index, 0), updated.count))
            nodes = updated
            return
        }

        guard let parentNode = node(id: parentID), case let .group(children) = parentNode.content else { return }
        guard let currentIndex = children.firstIndex(where: { $0.id == id }) else { return }
        var updatedChildren = children
        let moved = updatedChildren.remove(at: currentIndex)
        updatedChildren.insert(moved, at: min(max(index, 0), updatedChildren.count))

        var updatedParent = parentNode
        updatedParent.content = .group(children: updatedChildren)
        replace(updatedParent)
    }
}
