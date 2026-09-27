import AppKit
import SceauCore
import SwiftUI

/// Dialog „Leinwandgrösse ändern" als Sheet am Dokumentfenster.
///
/// Die Logik (welche Vorlage gilt, wann „Anwenden" möglich ist) steckt in
/// ``CanvasSizeForm``; hier wird nur angezeigt und am Ende ein einziger
/// Undo-Schritt geschrieben.
@MainActor
enum CanvasSizeDialog {

    static func present(for store: DocumentStore, in window: NSWindow) {
        guard window.attachedSheet == nil else { return }

        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        // `weak`: Solange das Sheet angezeigt wird, hält es das Fenster;
        // eine starke Referenz aus dem eigenen Inhalt wäre ein Kreis.
        let view = CanvasSizeView(form: CanvasSizeForm(size: store.document.artboard.size)) { [weak sheet, weak window] size in
            if let size {
                store.apply("Leinwandgrösse ändern") { $0.artboard.size = size }
            }
            if let sheet { window?.endSheet(sheet) }
        }
        sheet.contentViewController = NSHostingController(rootView: view)
        window.beginSheet(sheet)
    }
}

private struct CanvasSizeView: View {
    @State var form: CanvasSizeForm
    /// `nil` bei „Abbrechen".
    let finish: (CGSize?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Leinwandgrösse ändern")
                .font(.headline)
            Text("Die Ebenen behalten ihre Grösse und Position relativ zur oberen linken Ecke.")
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Picker("Vorlage:", selection: presetBinding) {
                    ForEach(ArtboardPreset.groups) { group in
                        ForEach(group.presets) { preset in
                            Text("\(preset.name)  —  \(Int(preset.size.width)) × \(Int(preset.size.height))")
                                .tag(Optional(preset.id))
                        }
                        Divider()
                    }
                    Text("Eigene Grösse").tag(String?.none)
                }
                // Ohne Tausendertrennzeichen: „3’508" wäre in einem
                // Pixelfeld eher verwirrend als hilfreich.
                TextField("Breite:", value: $form.width, format: .number.grouping(.never))
                TextField("Höhe:", value: $form.height, format: .number.grouping(.never))
            }

            if form.size == nil {
                Text("Breite und Höhe müssen zwischen 1 und \(CanvasSizeForm.maximumLength) liegen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Abbrechen") { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Anwenden") { finish(form.size) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(form.size == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var presetBinding: Binding<ArtboardPreset.ID?> {
        Binding(
            get: { form.preset?.id },
            set: { id in form.choose(ArtboardPreset.all.first { $0.id == id }) }
        )
    }
}
