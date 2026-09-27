import CoreGraphics
import Foundation
import Testing

@testable import SceauCore

/// Der sichtbare Verlauf (aus missing.md: „cmd z und y beides auch visuell").
///
/// Geprüft wird hier alles, was ohne AppKit-Ansicht auskommt: die Zählerstände
/// des Stores, die Geometrie der Zeitachse und das Springen zu einem früheren
/// Schritt. Die Ansicht selbst zeichnet und trifft danach keine eigenen
/// Entscheidungen mehr — sie fragt genau diese Werte ab.
@MainActor
@Suite("Verlauf — Zählerstände, Zeitachse, Sprung")
struct UndoTimelineTests {

    /// Der Undo-Manager wird mit zurückgegeben und muss von der Testmethode
    /// am Leben gehalten werden: `DocumentStore.undoManager` ist bewusst
    /// `weak` — im Programm gehört der Manager dem `NSDocument`.
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

    private func move(_ store: DocumentStore, to x: CGFloat) {
        store.apply("Bewegen") { document in
            guard case var .shape(spec) = document.nodes.first?.content,
                  var node = document.nodes.first
            else { return }
            spec.frame.origin.x = x
            node.content = .shape(spec)
            document.replace(node)
        }
    }

    private func firstX(_ store: DocumentStore) -> CGFloat? {
        guard case let .shape(spec) = store.document.nodes.first?.content else { return nil }
        return spec.frame.origin.x
    }

    // MARK: - Zählerstände

    @Test("Jede Änderung erhöht die Verlaufstiefe")
    func changesRaiseUndoDepth() {
        let (store, undo) = makeStore()
        #expect(store.undoDepth == 0)
        #expect(store.redoDepth == 0)

        move(store, to: 20)
        move(store, to: 40)

        #expect(store.undoDepth == 2)
        #expect(store.redoDepth == 0)
        withExtendedLifetime(undo) {}
    }

    /// Die Grundlage dafür, dass ein Zug über die Zeitachse nicht zu weit
    /// springt: Die Zähler sind auch in einer engen Schleife ohne
    /// Durchlauf der Ereignisschleife nach jedem einzelnen Schritt aktuell.
    @Test("Widerrufen und Wiederholen verschieben die Zähler sofort")
    func undoAndRedoShiftTheDepthsImmediately() {
        let (store, undo) = makeStore()
        for x in [20.0, 40.0, 60.0] as [CGFloat] { move(store, to: x) }
        #expect(store.undoDepth == 3)

        for expected in [2, 1, 0] {
            undo.undo()
            #expect(store.undoDepth == expected)
            #expect(store.redoDepth == 3 - expected)
        }
        for expected in [1, 2, 3] {
            undo.redo()
            #expect(store.undoDepth == expected)
            #expect(store.redoDepth == 3 - expected)
        }
    }

    @Test("Eine neue Änderung nach dem Widerrufen verwirft den vorderen Teil")
    func aNewChangeDropsTheRedoBranch() {
        let (store, undo) = makeStore()
        move(store, to: 20)
        move(store, to: 40)
        undo.undo()
        #expect(store.redoDepth == 1)

        move(store, to: 99)
        #expect(store.undoDepth == 2)
        #expect(store.redoDepth == 0)
    }

    // MARK: - Sprung im Verlauf

    @Test("Ein Sprung führt genau auf die verlangte Tiefe")
    func jumpReachesTheRequestedDepth() {
        let (store, undo) = makeStore()
        for x in [20.0, 40.0, 60.0] as [CGFloat] { move(store, to: x) }

        store.jump(toDepth: 1)
        #expect(store.undoDepth == 1)
        #expect(store.redoDepth == 2)
        #expect(firstX(store) == 20)

        store.jump(toDepth: 3)
        #expect(store.undoDepth == 3)
        #expect(firstX(store) == 60)

        store.jump(toDepth: 0)
        #expect(store.undoDepth == 0)
        #expect(firstX(store) == 0)
        withExtendedLifetime(undo) {}
    }

    @Test("Tiefen ausserhalb des Verlaufs werden begrenzt statt zu blockieren")
    func jumpClampsOutOfRangeDepths() {
        let (store, undo) = makeStore()
        move(store, to: 20)
        move(store, to: 40)

        store.jump(toDepth: 99)
        #expect(store.undoDepth == 2)

        store.jump(toDepth: -5)
        #expect(store.undoDepth == 0)
        #expect(store.redoDepth == 2)
        withExtendedLifetime(undo) {}
    }

    // MARK: - Geometrie der Zeitachse

    @Test("Die waagerechte Position bildet die Verlaufstiefe ab")
    func horizontalPositionMapsToHistoryDepth() {
        let geometry = UndoTimelineGeometry(width: 140, undoDepth: 4, redoDepth: 4)

        #expect(geometry.totalDepth == 8)
        #expect(geometry.depth(atX: 1) == 0)
        #expect(geometry.depth(atX: 70) == 4)
        #expect(geometry.depth(atX: 139) == 8)
        // Ausserhalb der Linie wird auf die Enden begrenzt.
        #expect(geometry.depth(atX: -20) == 0)
        #expect(geometry.depth(atX: 500) == 8)
    }

    @Test("Die Marke steht am Übergang zwischen getanem und widerrufenem Teil")
    func markerSitsBetweenDoneAndUndonePart() {
        let geometry = UndoTimelineGeometry(width: 140, undoDepth: 2, redoDepth: 6)
        #expect(abs(geometry.markerFraction - 0.25) < 0.0001)
        #expect(abs(geometry.markerX - (1 + 138 * 0.25)) < 0.0001)

        // Ein leerer Verlauf zeigt die Marke am Ende: Man steht auf dem
        // aktuellen Stand, es gibt nichts davor und nichts danach.
        let empty = UndoTimelineGeometry(width: 140, undoDepth: 0, redoDepth: 0)
        #expect(empty.markerFraction == 1)
        #expect(empty.markerX == empty.lineMaxX)
    }

    @Test("Rasterpunkte liegen gleichmässig auf der Linie")
    func stepPositionsAreEvenlySpaced() {
        let geometry = UndoTimelineGeometry(width: 141, undoDepth: 2, redoDepth: 2)
        #expect(geometry.x(forStep: 0) == geometry.lineMinX)
        #expect(geometry.x(forStep: 4) == geometry.lineMaxX)
        #expect(abs(geometry.x(forStep: 2) - (geometry.lineMinX + geometry.lineMaxX) / 2) < 0.0001)
    }

    /// Ohne diese Entprellung löste jedes Mauspixel eine vollständige Folge
    /// von Widerrufen aus — ein Zug über die Achse wäre unbedienbar.
    @Test("Ein Zug meldet jede Rasterposition nur einmal")
    func pointerReportsOnlyActualGridChanges() {
        let geometry = UndoTimelineGeometry(width: 140, undoDepth: 4, redoDepth: 4)
        var pointer = UndoTimelinePointer()
        pointer.begin()

        var reported: [Int] = []
        for x in [1, 2, 9, 10, 11, 26, 27] as [CGFloat] {
            if let depth = pointer.report(atX: x, geometry: geometry) { reported.append(depth) }
        }

        #expect(reported == [0, 1, 2])

        // Ein neuer Zug darf dieselbe Position wieder melden.
        pointer.begin()
        #expect(pointer.report(atX: 27, geometry: geometry) == 2)
    }
}
