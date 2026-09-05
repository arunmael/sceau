import AppKit
import SceauCore
import UniformTypeIdentifiers

/// Export in die drei Formate, die eine Logo-App wirklich braucht.
///
/// Der Entwicklungsplan verlangt „von der ersten Form bis zum fertigen SVG/PNG
/// nie mehr als ein, zwei Klicks" — deshalb führt jeder Eintrag direkt zum
/// Sichern-Dialog, ohne Zwischendialog mit Einstellungen.
@MainActor
enum ExportCommands {

    /// Die üblichen Kantenlängen eines App-Icon-Satzes.
    static let iconSizes = [16, 32, 64, 128, 256, 512, 1024]

    // MARK: - Einzeldateien

    static func exportSVG(from store: DocumentStore, in window: NSWindow) {
        let svg = SVGExporter.export(store.document)
        savePanel(suggested: "Logo.svg", type: .svg, in: window) { url in
            guard let data = svg.data(using: .utf8) else {
                throw ExportFailure.encoding
            }
            try data.write(to: url, options: .atomic)
        }
    }

    static func exportPDF(from store: DocumentStore, in window: NSWindow) {
        let document = store.document
        savePanel(suggested: "Logo.pdf", type: .pdf, in: window) { url in
            let data = try PDFExporter.pdfData(document)
            try data.write(to: url, options: .atomic)
        }
    }

    static func exportPNG(from store: DocumentStore, in window: NSWindow, scale: Int) {
        let document = store.document
        let width = RasterExporter.safePixelLength(document.artboard.size.width, scale: CGFloat(scale))
        let height = RasterExporter.safePixelLength(document.artboard.size.height, scale: CGFloat(scale))

        savePanel(suggested: "Logo.png", type: .png, in: window) { url in
            let data = try RasterExporter.pngData(document, pixelWidth: width, pixelHeight: height)
            try data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Icon-Satz

    /// Schreibt alle üblichen Icon-Grössen in einem Durchgang in einen Ordner.
    static func exportIconSet(from store: DocumentStore, in window: NSWindow) {
        let document = store.document

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Sichern"
        panel.message = "Ordner für den Icon-Satz wählen"

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let directory = panel.url else { return }
            do {
                let images = try RasterExporter.iconSet(document, sizes: iconSizes)
                for image in images {
                    let url = directory.appendingPathComponent("icon_\(image.size)x\(image.size).png")
                    try image.data.write(to: url, options: .atomic)
                }
            } catch {
                presentFailure(error, in: window)
            }
        }
    }

    // MARK: - Hilfen

    private enum ExportFailure: LocalizedError {
        case encoding

        var errorDescription: String? {
            "Die Datei konnte nicht geschrieben werden."
        }
    }

    private static func savePanel(
        suggested name: String,
        type: UTType,
        in window: NSWindow,
        write: @escaping (URL) throws -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try write(url)
            } catch {
                presentFailure(error, in: window)
            }
        }
    }

    private static func presentFailure(_ error: Error, in window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Export fehlgeschlagen"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }
}
