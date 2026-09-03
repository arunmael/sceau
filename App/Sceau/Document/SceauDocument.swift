import AppKit
import SceauCore
import UniformTypeIdentifiers

/// Fehler beim Lesen einer Dokumentdatei.
enum DocumentReadError: LocalizedError {
    case unsupportedFormatVersion(found: Int, supported: Int)
    case corrupt(underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormatVersion(found, supported):
            return "Diese Datei wurde mit einer neueren Version von Sceau erstellt "
                + "(Format \(found), unterstützt wird bis \(supported))."
        case .corrupt:
            return "Die Datei konnte nicht gelesen werden — der Inhalt ist beschädigt."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unsupportedFormatVersion:
            return "Aktualisiere Sceau, um die Datei zu öffnen."
        case .corrupt:
            return "Über „Ablage › Zurücksetzen auf“ lässt sich eine frühere Version wiederherstellen."
        }
    }
}

/// Das Dokument der App.
///
/// Bewusst `NSDocument` statt einer eigenen Verwaltung: damit kommen Autosave,
/// Absturz-Wiederherstellung und vor allem der eingebaute Versionsbrowser
/// („Ablage › Zurücksetzen auf › Alle Versionen durchsuchen …") ohne Eigenbau
/// mit — genau die Anforderungen aus Abschnitt 2.1 des Entwicklungsplans.
final class SceauDocument: NSDocument {

    /// Der Zustand dieses Dokuments. Wird bei `read(from:ofType:)` ersetzt,
    /// weshalb Fenster und Paletten ihn nie zwischenspeichern dürfen.
    private(set) var store: DocumentStore

    static let documentType = "ch.arunmeyer.sceau.document"

    override init() {
        store = DocumentStore(document: .empty())
        super.init()
        connectStore()
    }

    /// Autosave in place — Voraussetzung dafür, dass macOS automatisch
    /// Versionen anlegt und offene Dokumente nach einem Absturz wiederherstellt.
    override class var autosavesInPlace: Bool { true }

    /// Zusätzlich beim Wechsel in den Hintergrund sichern, damit zwischen zwei
    /// automatischen Sicherungen möglichst wenig verloren gehen kann.
    override class var preservesVersions: Bool { true }

    private func connectStore() {
        store.undoManager = undoManager
        store.didChange = { [weak self] in
            self?.updateChangeCount(.changeDone)
        }
    }

    // MARK: - Lesen und Schreiben

    override func data(ofType typeName: String) throws -> Data {
        let encoder = JSONEncoder()
        // Sortierte Schlüssel und Einrückung: so bleiben Änderungen an einer
        // Datei zwischen zwei Sicherungen in der Versionsverwaltung lesbar.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(store.document)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded: Document
        do {
            decoded = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw DocumentReadError.corrupt(underlying: error)
        }

        guard decoded.formatVersion <= Document.currentFormatVersion else {
            throw DocumentReadError.unsupportedFormatVersion(
                found: decoded.formatVersion,
                supported: Document.currentFormatVersion
            )
        }

        // `read(from:ofType:)` ist nicht an den Hauptthread gebunden, weil
        // NSDocument Dateien nebenläufig lesen darf — aber nur, wenn
        // `canConcurrentlyReadDocuments` true liefert. Das bleibt hier bei der
        // Vorgabe false, also läuft dieser Aufruf tatsächlich auf dem
        // Hauptthread, und die Zusicherung ist zutreffend statt bloss bequem.
        MainActor.assumeIsolated {
            store = DocumentStore(document: decoded)
            connectStore()
        }
    }

    /// Bleibt bewusst bei `false`: Der Dokumentzustand hängt am Hauptthread
    /// (siehe ``read(from:ofType:)``). Ein Umstellen auf nebenläufiges Lesen
    /// müsste diese Annahme mit auflösen.
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool {
        false
    }

    // MARK: - Fenster

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(store: store))
    }

    // MARK: - Menübefehle

    /// „Version jetzt sichern" — legt bewusst einen Wiederherstellungspunkt an,
    /// etwa vor einer riskanten booleschen Operation.
    @IBAction func saveVersionNow(_ sender: Any?) {
        guard fileURL != nil else {
            // Ungesicherte Dokumente haben noch keine Versionshistorie; der
            // normale Sichern-Dialog ist hier das Richtige.
            save(sender)
            return
        }
        updateChangeCount(.changeDone)
        save(sender)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(saveVersionNow(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
