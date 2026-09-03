import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

@Suite("Document — Knoten beliebiger Tiefe nachschlagen")
struct DocumentLookupTests {

    /// Aufbau:
    ///   [0] unten
    ///   [1] Gruppe
    ///         [0] innenA
    ///         [1] innenB
    ///   [2] oben
    private func makeDocument() -> (Document, [String: UUID]) {
        let unten = Node(name: "unten", shapeFrame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let innenA = Node(name: "innenA", shapeFrame: CGRect(x: 20, y: 0, width: 10, height: 10))
        let innenB = Node(name: "innenB", shapeFrame: CGRect(x: 40, y: 0, width: 10, height: 10))
        let gruppe = Node(name: "Gruppe", content: .group(children: [innenA, innenB]))
        let oben = Node(name: "oben", shapeFrame: CGRect(x: 60, y: 0, width: 10, height: 10))

        var document = Document.empty()
        document.nodes = [unten, gruppe, oben]

        return (document, [
            "unten": unten.id, "gruppe": gruppe.id,
            "innenA": innenA.id, "innenB": innenB.id, "oben": oben.id
        ])
    }

    @Test("Der Index innerhalb der eigenen Ebene wird gefunden")
    func indexWithinOwnLevel() {
        let (document, ids) = makeDocument()

        #expect(document.indexInParent(of: ids["unten"]!) == 0)
        #expect(document.indexInParent(of: ids["gruppe"]!) == 1)
        #expect(document.indexInParent(of: ids["oben"]!) == 2)
        // Kinder zählen innerhalb ihrer Gruppe, nicht im Dokument.
        #expect(document.indexInParent(of: ids["innenA"]!) == 0)
        #expect(document.indexInParent(of: ids["innenB"]!) == 1)
    }

    @Test("Eine unbekannte Kennung liefert keinen Index")
    func unknownIdentityHasNoIndex() {
        let (document, _) = makeDocument()
        #expect(document.indexInParent(of: UUID()) == nil)
    }

    @Test("Knoten werden in Zeichenreihenfolge geliefert, auch aus Gruppen")
    func nodesComeInDrawingOrder() {
        let (document, ids) = makeDocument()

        let selection: Set<UUID> = [ids["oben"]!, ids["innenB"]!, ids["unten"]!]
        let found = document.nodes(with: selection).map(\.name)

        // Zeichenreihenfolge: unten, dann der Gruppeninhalt, dann oben.
        #expect(found == ["unten", "innenB", "oben"])
    }

    @Test("Unbekannte Kennungen werden übergangen statt zu stören")
    func unknownIdentitiesAreSkipped() {
        let (document, ids) = makeDocument()
        let found = document.nodes(with: [ids["unten"]!, UUID()])
        #expect(found.map(\.name) == ["unten"])
    }

    @Test("Eine leere Auswahl liefert nichts")
    func emptySelectionYieldsNothing() {
        let (document, _) = makeDocument()
        #expect(document.nodes(with: []).isEmpty)
    }

    @Test("Auch eine Gruppe selbst lässt sich nachschlagen")
    func groupItselfIsFound() {
        let (document, ids) = makeDocument()
        let found = document.nodes(with: [ids["gruppe"]!])
        #expect(found.count == 1)
        #expect(found[0].isGroup)
    }
}

private extension Node {
    /// Kurzschreibweise für die Testaufbauten.
    init(name: String, shapeFrame: CGRect) {
        self.init(name: name, content: .shape(.rectangle(frame: shapeFrame, cornerRadius: 0)))
    }
}
