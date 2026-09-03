import AppKit
import SceauCore

/// Kopieren, Ausschneiden und Einsetzen von Zeichenobjekten.
///
/// Es wird ein **eigener** Zwischenablagetyp verwendet und nicht etwa SVG:
/// Beim Zurücklesen soll exakt dasselbe Dokumentmodell entstehen, das kopiert
/// wurde — parametrische Formen also weiterhin parametrisch, mitsamt Gruppen
/// und Stil. Ein Umweg über ein Austauschformat würde genau das verlieren.
@MainActor
enum ClipboardCommands {

    /// Eigener Typ für den Ausschnitt aus einem Sceau-Dokument.
    static let pasteboardType = NSPasteboard.PasteboardType("ch.arunmeyer.sceau.nodes")

    /// Versatz, mit dem Eingesetztes gegenüber dem Original erscheint, damit es
    /// nicht deckungsgleich dahinter verschwindet.
    private static let pasteOffset = CGVector(dx: 12, dy: 12)

    // MARK: - Lesen und Schreiben

    static func copy(from store: DocumentStore, to pasteboard: NSPasteboard = .general) {
        let nodes = store.document.nodes.filter { store.selection.contains($0.id) }
        guard !nodes.isEmpty else { return }

        guard let data = try? JSONEncoder().encode(nodes) else { return }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: pasteboardType)
    }

    static func cut(from store: DocumentStore, to pasteboard: NSPasteboard = .general) {
        let ids = store.selection
        guard !ids.isEmpty else { return }

        copy(from: store, to: pasteboard)
        store.apply("Ausschneiden") { $0.remove(ids: ids) }
        store.clearSelection()
    }

    static func paste(into store: DocumentStore, from pasteboard: NSPasteboard = .general) {
        guard let nodes = clipboardNodes(from: pasteboard) else { return }

        var inserted: [UUID] = []
        store.apply("Einsetzen") { document in
            inserted = document.paste(nodes, offsetBy: pasteOffset)
        }
        if !inserted.isEmpty {
            store.selection = Set(inserted)
        }
    }

    /// Dupliziert die Auswahl, ohne die Zwischenablage anzufassen.
    ///
    /// Bewusst getrennt vom Kopieren: Wer etwas dupliziert, will meist nicht,
    /// dass dabei der Inhalt seiner Zwischenablage verloren geht.
    static func duplicate(in store: DocumentStore) {
        let nodes = store.document.nodes.filter { store.selection.contains($0.id) }
        guard !nodes.isEmpty else { return }

        var inserted: [UUID] = []
        store.apply("Duplizieren") { document in
            inserted = document.paste(nodes, offsetBy: pasteOffset)
        }
        if !inserted.isEmpty {
            store.selection = Set(inserted)
        }
    }

    static func canPaste(from pasteboard: NSPasteboard = .general) -> Bool {
        clipboardNodes(from: pasteboard)?.isEmpty == false
    }

    private static func clipboardNodes(from pasteboard: NSPasteboard) -> [Node]? {
        guard let data = pasteboard.data(forType: pasteboardType) else { return nil }
        return try? JSONDecoder().decode([Node].self, from: data)
    }
}
