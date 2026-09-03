import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("Node — Kopien mit eigener Kennung")
struct NodeIdentityTests {

    private func groupWithChildren() -> Node {
        Node(
            name: "Gruppe",
            content: .group(children: [
                Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 2)),
                Node(
                    name: "Untergruppe",
                    content: .group(children: [
                        Node(shape: .ellipse(frame: CGRect(x: 5, y: 5, width: 20, height: 20)))
                    ])
                )
            ])
        )
    }

    @Test("Die Kopie bekommt eine andere Kennung")
    func copyGetsNewIdentity() {
        let original = Node(shape: .ellipse(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let copy = original.duplicated()

        #expect(copy.id != original.id)
        #expect(copy.content == original.content)
        #expect(copy.style == original.style)
        #expect(copy.name == original.name)
    }

    @Test("Auch alle Nachfahren bekommen neue Kennungen")
    func descendantsGetNewIdentities() {
        let original = groupWithChildren()
        let copy = original.duplicated()

        let originalIDs = Set(original.flattenedIDs)
        let copyIDs = Set(copy.flattenedIDs)

        #expect(originalIDs.count == 4)
        #expect(copyIDs.count == 4)
        #expect(originalIDs.isDisjoint(with: copyIDs), "keine einzige Kennung darf doppelt vorkommen")
    }

    @Test("Der Aufbau bleibt bis in die Tiefe erhalten")
    func structureIsPreserved() {
        let copy = groupWithChildren().duplicated()

        #expect(copy.children?.count == 2)
        let nested = copy.children?[1].children
        #expect(nested?.count == 1)
        if case let .shape(spec) = nested?[0].content {
            #expect(spec.frame == CGRect(x: 5, y: 5, width: 20, height: 20))
        } else {
            Issue.record("Die verschachtelte Form ging verloren")
        }
    }

    @Test("Zwei Kopien desselben Knotens kollidieren nicht miteinander")
    func twoCopiesAreDistinct() {
        let original = groupWithChildren()
        let first = original.duplicated()
        let second = original.duplicated()

        #expect(Set(first.flattenedIDs).isDisjoint(with: Set(second.flattenedIDs)))
    }
}

@Suite("Document — Einsetzen aus der Zwischenablage")
struct DocumentPasteTests {

    @Test("Eine Knotenliste übersteht die JSON-Rundreise der Zwischenablage")
    func nodeListSurvivesJSONRoundTrip() throws {
        let nodes = [
            Node(shape: .rectangle(frame: CGRect(x: 1, y: 2, width: 3, height: 4), cornerRadius: 1)),
            Node(
                name: "Gruppe",
                content: .group(children: [
                    Node(shape: .ellipse(frame: CGRect(x: 5, y: 6, width: 7, height: 8)))
                ])
            )
        ]

        let data = try JSONEncoder().encode(nodes)
        let restored = try JSONDecoder().decode([Node].self, from: data)

        #expect(restored == nodes)
    }

    @Test("Eingesetzte Knoten landen zuoberst und leicht versetzt")
    func pastedNodesGoOnTopWithOffset() {
        var document = Document.empty()
        let existing = Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0))
        document.nodes = [existing]

        let clipboard = [Node(shape: .ellipse(frame: CGRect(x: 100, y: 100, width: 50, height: 50)))]
        let inserted = document.paste(clipboard, offsetBy: CGVector(dx: 10, dy: 10))

        #expect(document.nodes.count == 2)
        #expect(document.nodes.last?.id == inserted.first)
        guard case let .shape(spec) = document.nodes[1].content else {
            Issue.record("Erwartet wurde eine Form")
            return
        }
        #expect(spec.frame.origin == CGPoint(x: 110, y: 110))
    }

    @Test("Mehrfaches Einsetzen erzeugt jedes Mal neue Kennungen")
    func repeatedPasteKeepsIdentitiesUnique() {
        var document = Document.empty()
        let clipboard = [Node(shape: .ellipse(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))]

        _ = document.paste(clipboard, offsetBy: .zero)
        _ = document.paste(clipboard, offsetBy: .zero)

        let ids = document.nodes.flatMap(\.flattenedIDs)
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2, "beide Einfügungen müssen eigene Kennungen haben")
    }

    @Test("Leere Zwischenablage verändert nichts")
    func emptyClipboardChangesNothing() {
        var document = Document.empty()
        let before = document
        let inserted = document.paste([], offsetBy: CGVector(dx: 5, dy: 5))

        #expect(inserted.isEmpty)
        #expect(document == before)
    }
}
