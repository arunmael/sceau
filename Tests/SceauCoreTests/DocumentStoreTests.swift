import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

/// Tests der App-Schicht.
///
/// Undo ist hier die eigentliche Knacknuss: Es hängt an `UndoManager` und damit
/// an AppKit, lässt sich also nicht im Paket `SceauCore` prüfen. Genau deshalb
/// gibt es dieses Ziel — ungetestet darf ausgerechnet die Funktion nicht
/// bleiben, die im Fehlerfall Arbeit vernichtet.
@MainActor
@Suite("DocumentStore — Änderungen und Widerrufen")
struct DocumentStoreTests {

    /// Ein Store mit eigenem Undo-Manager.
    ///
    /// `groupsByEvent` wird abgeschaltet: Sonst fasst `UndoManager` alles
    /// zusammen, was im selben Durchlauf der Ereignisschleife registriert
    /// wurde, und der Test prüfte nicht mehr das, was er zu prüfen vorgibt.
    private func makeStore() -> (DocumentStore, UndoManager) {
        let undo = UndoManager()
        undo.groupsByEvent = false

        var document = Document(artboard: Artboard(size: CGSize(width: 200, height: 200)))
        document.nodes = [
            Node(shape: .rectangle(frame: CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0))
        ]

        let store = DocumentStore(document: document)
        store.undoManager = undo
        return (store, undo)
    }

    private func firstFrame(_ store: DocumentStore) -> CGRect? {
        guard case let .shape(spec) = store.document.nodes.first?.content else { return nil }
        return spec.frame
    }

    @Test("Eine Änderung lässt sich widerrufen")
    func changeCanBeUndone() {
        let (store, undo) = makeStore()
        let before = firstFrame(store)

        store.apply("Bewegen") { document in
            guard let node = document.nodes.first else { return }
            document.replace(NodeTransform.moved(node, by: CGVector(dx: 25, dy: 0)))
        }
        #expect(firstFrame(store)?.minX == 25)

        undo.undo()
        #expect(firstFrame(store) == before)
    }

    @Test("Widerrufenes lässt sich wiederholen")
    func undoneChangeCanBeRedone() {
        let (store, undo) = makeStore()

        store.apply("Bewegen") { document in
            guard let node = document.nodes.first else { return }
            document.replace(NodeTransform.moved(node, by: CGVector(dx: 25, dy: 0)))
        }
        undo.undo()
        undo.redo()

        #expect(firstFrame(store)?.minX == 25)
    }

    @Test("Eine Änderung ohne Wirkung erzeugt keinen Widerrufsschritt")
    func noopChangeRegistersNothing() {
        let (store, undo) = makeStore()
        store.apply("Nichts") { _ in }

        #expect(!undo.canUndo, "sonst sammelt sich beim blossen Anklicken Leerlauf an")
    }

    @Test("Der Aktionsname landet im Menü")
    func actionNameIsSet() {
        let (store, undo) = makeStore()
        store.apply("Form hinzufügen") { document in
            document.appendOnTop(Node(shape: .ellipse(frame: CGRect(x: 0, y: 0, width: 5, height: 5))))
        }
        #expect(undo.undoActionName == "Form hinzufügen")
    }

    @Test("Schreiben ohne Undo registriert keinen Schritt")
    func writingWithoutUndoRegistersNothing() {
        let (store, undo) = makeStore()
        var draft = store.document
        draft.appendOnTop(Node(shape: .ellipse(frame: CGRect(x: 0, y: 0, width: 5, height: 5))))
        store.setDocumentWithoutUndo(draft)

        #expect(store.document.nodes.count == 2)
        #expect(!undo.canUndo)
    }

    @Test("Eine zusammengefasste Folge ergibt genau einen Widerrufsschritt")
    func coalescedRunIsASingleUndoStep() {
        let (store, undo) = makeStore()
        let before = firstFrame(store)

        // Der Endwert muss sich vom Ausgangswert (Vorgabe 1) unterscheiden,
        // sonst prüfte der Test nichts: Eine Folge, die per Saldo nichts
        // ändert, darf zu Recht gar keinen Schritt hinterlassen.
        // Exakt darstellbare Werte, damit der Vergleich am Ende nicht an
        // Fliesskomma-Rundung scheitert statt an der Sache.
        let steps: [CGFloat] = [0.875, 0.75, 0.625, 0.5, 0.375, 0.3125, 0.28125, 0.25]
        store.beginCoalescing("Deckkraft ändern")
        for value in steps {
            store.apply("Zwischenwert") { document in
                guard var node = document.nodes.first else { return }
                node.style.opacity = value
                document.replace(node)
            }
        }
        store.endCoalescing()

        #expect(store.document.nodes.first?.style.opacity == 0.25)
        #expect(undo.undoActionName == "Deckkraft ändern")

        undo.undo()
        #expect(store.document.nodes.first?.style.opacity == 1.0, "Ausgangswert war die Vorgabe 1")
        #expect(firstFrame(store) == before)
        #expect(!undo.canUndo, "acht Zwischenwerte dürfen nur einen Schritt hinterlassen")
    }

    @Test("Eine zusammengefasste Folge ohne Wirkung hinterlässt nichts")
    func emptyCoalescedRunLeavesNothing() {
        let (store, undo) = makeStore()
        store.beginCoalescing("Deckkraft ändern")
        store.endCoalescing()

        #expect(!undo.canUndo)
    }

    @Test("Widerrufen räumt verwaiste Auswahl-Kennungen ab")
    func undoPrunesStaleSelection() {
        let (store, undo) = makeStore()
        let added = Node(shape: .ellipse(frame: CGRect(x: 0, y: 0, width: 5, height: 5)))

        store.apply("Form hinzufügen") { $0.appendOnTop(added) }
        store.selection = [added.id]

        undo.undo()
        #expect(!store.selection.contains(added.id), "die Auswahl darf nicht auf gelöschte Knoten zeigen")
    }
}
