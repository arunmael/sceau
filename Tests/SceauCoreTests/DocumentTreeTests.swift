import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("DocumentTree — Baumoperationen")
struct DocumentTreeTests {

    // MARK: - Helfer

    private func leaf(_ name: String) -> Node {
        Node(name: name, content: .shape(.rectangle(frame: .zero, cornerRadius: 0)))
    }

    private func group(_ name: String, children: [Node]) -> Node {
        Node(name: name, content: .group(children: children))
    }

    private func document(nodes: [Node]) -> Document {
        Document(artboard: Artboard(size: CGSize(width: 100, height: 100)), nodes: nodes)
    }

    // MARK: - Finden / Ersetzen

    @Test("node(id:) findet einen Knoten in Tiefe 3")
    func findsDeeplyNestedNode() {
        let innerLeaf = leaf("Blatt")
        let innerGroup = group("Innen", children: [innerLeaf])
        let outerGroup = group("Aussen", children: [innerGroup])
        let doc = document(nodes: [outerGroup])

        let found = doc.node(id: innerLeaf.id)
        #expect(found?.id == innerLeaf.id)
        #expect(found?.name == "Blatt")
    }

    @Test("replace(_:) ersetzt einen Knoten in Tiefe 3 an Ort und Stelle")
    func replacesDeeplyNestedNodeInPlace() {
        let innerLeaf = leaf("Blatt")
        let innerGroup = group("Innen", children: [innerLeaf])
        let outerGroup = group("Aussen", children: [innerGroup])
        var doc = document(nodes: [outerGroup])

        var renamed = innerLeaf
        renamed.name = "Umbenannt"
        doc.replace(renamed)

        #expect(doc.node(id: innerLeaf.id)?.name == "Umbenannt")
        // Die Struktur drumherum bleibt unverändert.
        #expect(doc.nodes.count == 1)
        #expect(doc.nodes[0].children?[0].children?[0].name == "Umbenannt")
    }

    @Test("replace(_:) mit unbekannter ID tut nichts")
    func replaceWithUnknownIDIsNoOp() {
        var doc = document(nodes: [leaf("A")])
        let before = doc
        doc.replace(leaf("Unbekannt"))
        #expect(doc == before)
    }

    // MARK: - Entfernen

    @Test("Entfernen eines Elternteils entfernt auch dessen Kinder")
    func removingParentRemovesChildren() {
        let child = leaf("Kind")
        let parent = group("Eltern", children: [child])
        var doc = document(nodes: [leaf("Andere"), parent])

        doc.remove(ids: [parent.id])

        #expect(doc.node(id: parent.id) == nil)
        #expect(doc.node(id: child.id) == nil)
        #expect(doc.nodes.count == 1)
        #expect(doc.nodes[0].name == "Andere")
    }

    @Test("remove(ids:) mit unbekannten IDs tut nichts")
    func removeWithUnknownIDsIsNoOp() {
        var doc = document(nodes: [leaf("A"), leaf("B")])
        let before = doc
        doc.remove(ids: [UUID()])
        #expect(doc == before)
    }

    // MARK: - flattenedNodes / ancestors

    @Test("ancestors(of:) liefert die Kette vom obersten Vorfahren bis zum direkten Elternteil")
    func ancestorsReturnsCorrectChain() {
        let innerLeaf = leaf("Blatt")
        let innerGroup = group("Innen", children: [innerLeaf])
        let outerGroup = group("Aussen", children: [innerGroup])
        let doc = document(nodes: [outerGroup])

        let chain = doc.ancestors(of: innerLeaf.id)
        #expect(chain.map(\.id) == [outerGroup.id, innerGroup.id])

        // Ein Wurzelknoten hat keine Vorfahren.
        #expect(doc.ancestors(of: outerGroup.id).isEmpty)

        // Unbekannte ID: leere Kette statt Absturz.
        #expect(doc.ancestors(of: UUID()).isEmpty)
    }

    @Test("flattenedNodes rollt Gruppen samt Kindern in Zeichenreihenfolge aus")
    func flattenedNodesUnrollsGroups() {
        let innerLeaf = leaf("Blatt")
        let innerGroup = group("Innen", children: [innerLeaf])
        let doc = document(nodes: [leaf("Unten"), innerGroup])

        let names = doc.flattenedNodes.map(\.name)
        #expect(names == ["Unten", "Innen", "Blatt"])
    }

    // MARK: - Gruppieren

    @Test("group(ids:name:) erhält die Z-Reihenfolge und setzt die Gruppe an die Position des obersten Mitglieds")
    func groupingPreservesZOrderAndTopPosition() {
        let a = leaf("A")
        let b = leaf("B")
        let c = leaf("C")
        let d = leaf("D")
        var doc = document(nodes: [a, b, c, d]) // Index 0 = zuunterst

        // A und C werden gruppiert; C ist das obere der beiden Mitglieder.
        guard let groupID = doc.group(ids: [a.id, c.id], name: "Gruppe") else {
            Issue.record("Gruppierung sollte gelingen")
            return
        }

        #expect(doc.nodes.map(\.name) == ["B", "Gruppe", "D"])
        let groupNode = doc.node(id: groupID)
        #expect(groupNode?.children?.map(\.name) == ["A", "C"])
    }

    @Test("Gruppieren mit weniger als zwei gruppierbaren Knoten gibt nil zurück")
    func groupingWithFewerThanTwoNodesFails() {
        var doc = document(nodes: [leaf("A"), leaf("B")])
        let result = doc.group(ids: [doc.nodes[0].id], name: "Gruppe")
        #expect(result == nil)
    }

    @Test("Auflösen macht das Gruppieren exakt rückgängig (Rundreise)")
    func ungroupIsExactRoundTripForContiguousMembers() {
        let a = leaf("A")
        let b = leaf("B")
        let c = leaf("C")
        var doc = document(nodes: [a, b, c])
        let originalOrder = doc.nodes.map(\.name)

        // B und C sind zusammenhängend (keine fremden Knoten dazwischen),
        // daher stellt das Auflösen exakt die ursprüngliche Reihenfolge wieder her.
        guard let groupID = doc.group(ids: [b.id, c.id], name: "Gruppe") else {
            Issue.record("Gruppierung sollte gelingen")
            return
        }

        let exposed = doc.ungroup(ids: [groupID])
        #expect(exposed == Set([b.id, c.id]))
        #expect(doc.nodes.map(\.name) == originalOrder)
        #expect(doc.node(id: groupID) == nil)
    }

    @Test("Gruppieren über Ebenengrenzen hinweg gruppiert nur die Mehrheitsebene")
    func groupingAcrossParentBoundariesUsesMostCommonParent() {
        let x = leaf("X")
        let y = leaf("Y")
        let outsider = leaf("Aussenseiter")
        let inner = group("Innen", children: [x, y])
        var doc = document(nodes: [outsider, inner])

        // x und y teilen sich "Innen" als Elternteil, outsider liegt auf der
        // Wurzelebene. Die Wurzelebene stellt nur ein einziges Mitglied,
        // "Innen" zwei — die Mehrheitsebene gewinnt, outsider bleibt unberührt.
        let result = doc.group(ids: [x.id, y.id, outsider.id], name: "Gruppe")
        #expect(result != nil)

        guard let groupID = result else { return }
        // outsider ist weiterhin ein eigenständiger Wurzelknoten.
        #expect(doc.nodes.contains { $0.id == outsider.id })
        // x und y stecken jetzt in der neuen, verschachtelten Gruppe.
        let newGroup = doc.node(id: groupID)
        let childIDs = Set(newGroup?.children?.map(\.id) ?? [])
        #expect(childIDs == Set([x.id, y.id]))
        // Die neue Gruppe hängt weiterhin unter "Innen".
        #expect(doc.ancestors(of: groupID).map(\.id) == [inner.id])
    }

    @Test("Gruppieren mit unbekannten IDs verhält sich unschädlich")
    func groupingWithUnknownIDsIsHarmless() {
        var doc = document(nodes: [leaf("A")])
        let result = doc.group(ids: [UUID(), UUID()], name: "Gruppe")
        #expect(result == nil)
    }

    @Test("ungroup(ids:) auf Nicht-Gruppen oder unbekannten IDs liefert eine leere Menge")
    func ungroupOnNonGroupsIsNoOp() {
        var doc = document(nodes: [leaf("A"), leaf("B")])
        let before = doc
        let exposed = doc.ungroup(ids: [doc.nodes[0].id, UUID()])
        #expect(exposed.isEmpty)
        #expect(doc == before)
    }

    // MARK: - Reorder

    @Test("reorder(id:to:) klemmt einen zu grossen oder negativen Index")
    func reorderClampsOutOfRangeIndex() {
        var doc = document(nodes: [leaf("A"), leaf("B"), leaf("C")])
        let aID = doc.nodes[0].id

        doc.reorder(id: aID, to: 999)
        #expect(doc.nodes.last?.id == aID)

        doc.reorder(id: aID, to: -50)
        #expect(doc.nodes.first?.id == aID)
    }

    @Test("reorder(id:to:) funktioniert innerhalb einer verschachtelten Gruppe")
    func reorderWorksInsideNestedGroup() {
        let x = leaf("X")
        let y = leaf("Y")
        let z = leaf("Z")
        let inner = group("Innen", children: [x, y, z])
        var doc = document(nodes: [inner])

        doc.reorder(id: x.id, to: 2)

        let children = doc.node(id: inner.id)?.children
        #expect(children?.map(\.name) == ["Y", "Z", "X"])
    }

    @Test("reorder(id:to:) mit unbekannter ID tut nichts")
    func reorderWithUnknownIDIsNoOp() {
        var doc = document(nodes: [leaf("A"), leaf("B")])
        let before = doc
        doc.reorder(id: UUID(), to: 0)
        #expect(doc == before)
    }
}
