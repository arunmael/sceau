import SwiftUI
import SceauCore

/// Die Ebenenliste links im Dokumentfenster.
///
/// Zeigt den Dokumentbaum in umgekehrter Z-Reihenfolge — ``Document/nodes``
/// hat Index 0 zuunterst, in der Liste soll aber das oberste Objekt oben
/// stehen, wie man es aus jeder Bildbearbeitung kennt. Gruppen bringen ihre
/// Kinder in derselben Konvention mit, die Umkehrung passiert deshalb an
/// jeder Ebene der Rekursion neu.
@MainActor
struct LayerListView: View {
    let store: DocumentStore

    @State private var renamingID: UUID?
    @State private var renameText: String = ""

    private var rootRows: [LayerRow] {
        LayerRow.makeRows(from: store.document.nodes)
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(get: { store.selection }, set: { store.selection = $0 })
    }

    var body: some View {
        List(selection: selectionBinding) {
            LayerOutlineRows(
                rows: rootRows,
                parentID: nil,
                store: store,
                renamingID: $renamingID,
                renameText: $renameText
            )
        }
        .listStyle(.sidebar)
    }
}

/// Ein Eintrag der Ebenenliste — der Knoten selbst plus seine Kinder, bereits
/// in Anzeige-Reihenfolge gebracht.
private struct LayerRow: Identifiable {
    let node: Node
    var children: [LayerRow]?

    var id: UUID { node.id }

    static func makeRows(from nodes: [Node]) -> [LayerRow] {
        nodes.reversed().map { node in
            LayerRow(node: node, children: node.children.map(makeRows(from:)))
        }
    }
}

/// Eine Ebene der Ausgabe: rendert die Zeilen und trägt per `onMove` die
/// Drag&Drop-Umsortierung innerhalb genau dieser Ebene ein.
private struct LayerOutlineRows: View {
    let rows: [LayerRow]
    /// `nil` heisst Wurzelebene, sonst die Gruppe, deren Kinder das hier sind.
    let parentID: UUID?
    let store: DocumentStore
    @Binding var renamingID: UUID?
    @Binding var renameText: String

    var body: some View {
        ForEach(rows) { row in
            if let children = row.children {
                DisclosureGroup {
                    LayerOutlineRows(
                        rows: children,
                        parentID: row.id,
                        store: store,
                        renamingID: $renamingID,
                        renameText: $renameText
                    )
                } label: {
                    LayerRowView(node: row.node, store: store, renamingID: $renamingID, renameText: $renameText)
                }
            } else {
                LayerRowView(node: row.node, store: store, renamingID: $renamingID, renameText: $renameText)
            }
        }
        .onMove { source, destination in
            move(source: source, to: destination)
        }
    }

    /// Bildet die neue Anzeige-Reihenfolge auf Modell-Reihenfolge zurück und
    /// schreibt sie über `store.apply`, damit ein Drag genau einen
    /// Undo-Schritt ergibt.
    private func move(source: IndexSet, to destination: Int) {
        var displayOrder = rows.map(\.id)
        displayOrder.move(fromOffsets: source, toOffset: destination)
        let modelOrder = Array(displayOrder.reversed())

        store.apply("Ebene verschieben") { document in
            if let parentID {
                guard var parent = document.node(id: parentID), let children = parent.children else { return }
                // `uniquingKeysWith` statt `uniqueKeysWithValues:` — eine von
                // Hand geänderte oder beschädigte Dokumentdatei kann doppelte
                // Kennungen enthalten; die harte Vorbedingung würde beim
                // Ziehen einer Ebene sofort abstürzen statt nur eine der
                // Dubletten zu verlieren.
                let byID = Dictionary(children.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                parent.content = .group(children: modelOrder.compactMap { byID[$0] })
                document.replace(parent)
            } else {
                let byID = Dictionary(document.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                document.nodes = modelOrder.compactMap { byID[$0] }
            }
        }
    }
}

/// Eine einzelne Zeile: Vorschau, Name (umbenennbar), Sichtbarkeit, Sperre.
private struct LayerRowView: View {
    let node: Node
    let store: DocumentStore
    @Binding var renamingID: UUID?
    @Binding var renameText: String

    var body: some View {
        HStack(spacing: 8) {
            LayerThumbnail(node: node)
                .frame(width: 20, height: 20)

            if renamingID == node.id {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .onSubmit(commitRename)
            } else {
                Text(node.name)
                    .lineLimit(1)
                    .opacity(node.isVisible ? 1 : 0.5)
                    .onTapGesture(count: 2) { beginRename() }
            }

            Spacer(minLength: 4)

            if node.isLocked {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }

            Button(action: toggleVisibility) {
                Image(systemName: node.isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(node.isVisible ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }

    private func beginRename() {
        renameText = node.name
        renamingID = node.id
    }

    private func commitRename() {
        defer { renamingID = nil }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != node.name else { return }
        var updated = node
        updated.name = trimmed
        store.apply("Umbenennen") { $0.replace(updated) }
    }

    private func toggleVisibility() {
        var updated = node
        updated.isVisible.toggle()
        store.apply(updated.isVisible ? "Ebene einblenden" : "Ebene ausblenden") { $0.replace(updated) }
    }
}

/// Die kleine Kontur-Vorschau links jeder Zeile.
///
/// Gruppen und Textknoten liefern über ``NodeGeometry`` womöglich einen leeren
/// Pfad (Text vor der Umwandlung in Phase 3, leere Gruppen) — dann zeigt die
/// Vorschau statt einer leeren Fläche ein passendes Symbol.
private struct LayerThumbnail: View {
    let node: Node

    private static let size: CGFloat = 20
    private static let inset: CGFloat = 3

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)

            if let path = scaledPath {
                path.fill(fillColor)
                path.stroke(.primary.opacity(0.3), lineWidth: 0.75)
            } else {
                Image(systemName: fallbackSymbol)
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var fallbackSymbol: String {
        switch node.content {
        case .group: return "square.stack.3d.up"
        case .text: return "textformat"
        default: return "square.dashed"
        }
    }

    private var fillColor: Color {
        switch node.style.fill {
        case let .solid(color):
            return Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
        case .linearGradient, .radialGradient, .pattern:
            return .secondary
        case .none:
            return .clear
        }
    }

    /// Die Kontur des Knotens, eingepasst und mittig zentriert in das
    /// Vorschau-Quadrat.
    private var scaledPath: Path? {
        let vectorPath = NodeGeometry.path(for: node)
        guard !vectorPath.isEmpty else { return nil }

        let bounds = vectorPath.bounds
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }

        let available = Self.size - Self.inset * 2
        let scale = min(available / bounds.width, available / bounds.height)
        let offsetX = Self.inset + (available - bounds.width * scale) / 2
        let offsetY = Self.inset + (available - bounds.height * scale) / 2

        var transform = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))

        guard let cgPath = vectorPath.cgPath.copy(using: &transform) else { return nil }
        return Path(cgPath)
    }
}
