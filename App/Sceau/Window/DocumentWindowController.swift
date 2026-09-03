import AppKit
import SwiftUI
import SceauCore

/// Das Dokumentfenster: Ebenen links, Zeichenfläche mittig, Eigenschaften rechts.
///
/// Der Aufbau folgt dem Grundsatz „ein Fenster, ein Fokus" aus dem
/// Entwicklungsplan — es gibt bewusst keine frei schwebenden Paletten.
final class DocumentWindowController: NSWindowController, NSUserInterfaceValidations {

    private let store: DocumentStore
    private var canvasView: CanvasView?

    init(store: DocumentStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 900, height: 600)

        super.init(window: window)

        window.contentViewController = makeSplitViewController()
        setUpToolbar()
        // Merkt sich Grösse und Position über Sitzungen hinweg.
        window.setFrameAutosaveName("SceauDocumentWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Nur programmatisch verwendet") }

    // MARK: - Aufbau

    private func makeSplitViewController() -> NSSplitViewController {
        let split = NSSplitViewController()

        let layers = NSHostingController(rootView: LayerListView(store: store))
        let layersItem = NSSplitViewItem(sidebarWithViewController: layers)
        layersItem.minimumThickness = 200
        layersItem.maximumThickness = 340
        layersItem.canCollapse = true

        let canvas = CanvasView(store: store)
        canvasView = canvas
        let canvasController = NSViewController()
        canvasController.view = canvas
        let canvasItem = NSSplitViewItem(viewController: canvasController)
        canvasItem.minimumThickness = 400

        let inspector = NSHostingController(rootView: InspectorView(store: store))
        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
        inspectorItem.minimumThickness = 240
        inspectorItem.maximumThickness = 360
        inspectorItem.canCollapse = true

        split.addSplitViewItem(layersItem)
        split.addSplitViewItem(canvasItem)
        split.addSplitViewItem(inspectorItem)

        // AppKit richtet die Fenstergrösse nach der bevorzugten Grösse des
        // Inhalts-Controllers. Ohne diese Angabe fällt das Fenster auf die
        // Summe der Mindestbreiten zusammen und startet unnötig eng.
        split.preferredContentSize = NSSize(width: 1280, height: 820)
        return split
    }

    private func setUpToolbar() {
        let toolbar = NSToolbar(identifier: "SceauToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    // MARK: - Werkzeuge

    @objc private func selectTool(_ sender: NSToolbarItem) {
        store.activeTool = .select
    }

    @objc private func choosePenTool(_ sender: Any?) {
        store.activeTool = .pen
    }

    @objc private func chooseTextTool(_ sender: Any?) {
        store.activeTool = .text
    }

    @objc private func chooseShapeTool(_ sender: NSMenuItem) {
        guard let tool = ToolKind(rawValue: sender.representedObject as? String ?? "") else { return }
        store.activeTool = tool
    }

    // MARK: - Pathfinder

    @objc private func performBooleanOperation(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let operation = BooleanOperation(rawValue: raw)
        else { return }
        PathfinderCommands.perform(operation, on: store, presentingIn: window)
    }

    /// Aufruf aus der Menüleiste, wo die Operation als Zeichenkette im
    /// `representedObject` steckt.
    @objc func performBooleanOperationFromMenu(_ sender: NSMenuItem) {
        performBooleanOperation(sender)
    }

    // MARK: - Anordnen und Gruppieren

    @objc func groupSelection(_ sender: Any?) {
        let ids = store.selection
        guard ids.count >= 2 else { return }
        var newGroupID: UUID?
        store.apply("Gruppieren") { document in
            newGroupID = document.group(ids: ids, name: "Gruppe")
        }
        if let newGroupID {
            store.selection = [newGroupID]
        }
    }

    @objc func ungroupSelection(_ sender: Any?) {
        let ids = store.selection
        guard !ids.isEmpty else { return }
        var freed: Set<UUID> = []
        store.apply("Gruppierung auflösen") { document in
            freed = document.ungroup(ids: ids)
        }
        if !freed.isEmpty {
            store.selection = freed
        }
    }

    @objc func bringForward(_ sender: Any?) {
        moveInZOrder(by: 1, actionName: "Nach vorne")
    }

    @objc func sendBackward(_ sender: Any?) {
        moveInZOrder(by: -1, actionName: "Nach hinten")
    }

    private func moveInZOrder(by delta: Int, actionName: String) {
        guard let id = store.selection.first, store.selection.count == 1,
              let index = store.document.nodes.firstIndex(where: { $0.id == id })
        else { return }

        store.apply(actionName) { document in
            document.reorder(id: id, to: index + delta)
        }
    }

    /// Ersetzt ausgewählte Textebenen durch ihre Konturen.
    ///
    /// Beim Weitergeben eines Logos ist das der entscheidende Schritt: Ein
    /// Pfad sieht überall gleich aus, ein Text nur dort, wo die Schrift
    /// installiert ist. Der Export macht das ohnehin automatisch — hier wird
    /// es sichtbar und weiter bearbeitbar im Dokument festgeschrieben.
    @objc func convertTextToOutlines(_ sender: Any?) {
        let textNodes = store.document.nodes.filter { node in
            guard store.selection.contains(node.id) else { return false }
            if case .text = node.content { return true }
            return false
        }
        guard !textNodes.isEmpty else { return }

        store.apply("Text in Pfade umwandeln") { document in
            for node in textNodes {
                guard case let .text(spec) = node.content else { continue }
                let path = TextToPath.path(for: spec)
                // Ein Text ohne Konturen (etwa eine leere Zeichenkette) bliebe
                // sonst als unsichtbarer, nicht mehr editierbarer Pfad zurück.
                guard !path.isEmpty else { continue }

                var converted = node
                converted.content = .path(path)
                converted.name = spec.string.isEmpty ? node.name : spec.string
                document.replace(converted)
            }
        }
    }

    // MARK: - Ausrichten

    @objc private func performAlignment(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        AlignmentCommands.perform(named: raw, on: store)
    }

    // MARK: - Export

    @objc private func performExport(_ sender: NSMenuItem) {
        guard let window, let key = sender.representedObject as? String else { return }

        switch key {
        case "svg": ExportCommands.exportSVG(from: store, in: window)
        case "pdf": ExportCommands.exportPDF(from: store, in: window)
        case "png1": ExportCommands.exportPNG(from: store, in: window, scale: 1)
        case "png2": ExportCommands.exportPNG(from: store, in: window, scale: 2)
        case "iconset": ExportCommands.exportIconSet(from: store, in: window)
        default: break
        }
    }

    // MARK: - Ansicht

    @objc func zoomToFit(_ sender: Any?) {
        store.zoom = 1
        canvasView?.centerArtboard()
    }

    @objc func zoomIn(_ sender: Any?) {
        setZoom(store.zoom * 1.25)
    }

    @objc func zoomOut(_ sender: Any?) {
        setZoom(store.zoom / 1.25)
    }

    private func setZoom(_ value: CGFloat) {
        store.zoom = min(64, max(0.05, value))
        canvasView?.centerArtboard()
    }

    @objc func toggleGrid(_ sender: Any?) {
        store.showsGrid.toggle()
        canvasView?.refresh()
    }

    @objc func toggleSnapping(_ sender: Any?) {
        store.snapsEnabled.toggle()
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        // Häkchen an den beiden Umschaltern, damit ihr Zustand ablesbar ist.
        if let menuItem = item as? NSMenuItem {
            switch item.action {
            case #selector(toggleGrid(_:)):
                menuItem.state = store.showsGrid ? .on : .off
            case #selector(toggleSnapping(_:)):
                menuItem.state = store.snapsEnabled ? .on : .off
            default:
                break
            }
        }
        return true
    }
}

// MARK: - Werkzeugleiste

extension DocumentWindowController: NSToolbarDelegate {

    private enum ItemID {
        static let select = NSToolbarItem.Identifier("select")
        static let shapes = NSToolbarItem.Identifier("shapes")
        static let pen = NSToolbarItem.Identifier("pen")
        static let text = NSToolbarItem.Identifier("text")
        static let pathfinder = NSToolbarItem.Identifier("pathfinder")
        static let align = NSToolbarItem.Identifier("align")
        static let export = NSToolbarItem.Identifier("export")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Genau sieben sichtbare Bedienelemente — mehr wäre laut
        // Entwicklungsplan bereits zu viel.
        [
            ItemID.select, ItemID.shapes, ItemID.pen, ItemID.text,
            .flexibleSpace,
            ItemID.pathfinder, ItemID.align,
            .flexibleSpace,
            ItemID.export
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case ItemID.select:
            return button(identifier, title: "Auswählen", symbol: "cursorarrow", action: #selector(selectTool(_:)))

        case ItemID.shapes:
            return menuItem(identifier, title: "Form", symbol: "square.on.circle", menu: shapeMenu())

        case ItemID.pen:
            return button(identifier, title: "Zeichenstift", symbol: "pencil.tip", action: #selector(choosePenTool(_:)))

        case ItemID.text:
            return button(identifier, title: "Text", symbol: "textformat", action: #selector(chooseTextTool(_:)))

        case ItemID.pathfinder:
            return menuItem(identifier, title: "Pathfinder", symbol: "square.on.square.dashed", menu: pathfinderMenu())

        case ItemID.align:
            return menuItem(identifier, title: "Ausrichten", symbol: "align.horizontal.left", menu: alignMenu())

        case ItemID.export:
            return menuItem(identifier, title: "Exportieren", symbol: "square.and.arrow.up", menu: exportMenu())

        default:
            return nil
        }
    }

    private func button(
        _ identifier: NSToolbarItem.Identifier,
        title: String,
        symbol: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = title
        item.paletteLabel = title
        item.toolTip = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    private func menuItem(
        _ identifier: NSToolbarItem.Identifier,
        title: String,
        symbol: String,
        menu: NSMenu
    ) -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = title
        item.paletteLabel = title
        item.toolTip = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.menu = menu
        item.showsIndicator = true
        return item
    }

    private func shapeMenu() -> NSMenu {
        let menu = NSMenu()
        for tool in [ToolKind.rectangle, .ellipse, .polygon, .star] {
            let entry = NSMenuItem(title: tool.title, action: #selector(chooseShapeTool(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = tool.rawValue
            entry.image = NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title)
            menu.addItem(entry)
        }
        return menu
    }

    private func pathfinderMenu() -> NSMenu {
        let menu = NSMenu()
        let entries: [(BooleanOperation, String, String)] = [
            (.union, "Vereinigen", "plus.square.on.square"),
            (.subtract, "Subtrahieren", "minus.square"),
            (.intersect, "Schnittmenge", "square.on.square.intersection.dashed"),
            (.exclude, "Ausschliessen", "square.on.square.squareshape.controlhandles")
        ]
        for (operation, title, symbol) in entries {
            let entry = NSMenuItem(title: title, action: #selector(performBooleanOperation(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = operation.rawValue
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            menu.addItem(entry)
        }
        return menu
    }

    private func exportMenu() -> NSMenu {
        let menu = NSMenu()
        let entries: [(String, String)] = [
            ("svg", "Als SVG …"),
            ("pdf", "Als PDF …"),
            ("-", ""),
            ("png1", "Als PNG (1×) …"),
            ("png2", "Als PNG (2×) …"),
            ("-", ""),
            ("iconset", "Icon-Satz (16 – 1024 px) …")
        ]
        for (key, title) in entries {
            if key == "-" {
                menu.addItem(.separator())
                continue
            }
            let entry = NSMenuItem(title: title, action: #selector(performExport(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = key
            menu.addItem(entry)
        }
        return menu
    }

    private func alignMenu() -> NSMenu {
        let menu = NSMenu()
        let entries: [(String, String)] = [
            ("left", "Links ausrichten"),
            ("centerX", "Horizontal zentrieren"),
            ("right", "Rechts ausrichten"),
            ("top", "Oben ausrichten"),
            ("centerY", "Vertikal zentrieren"),
            ("bottom", "Unten ausrichten"),
            ("-", ""),
            ("distributeH", "Horizontal verteilen"),
            ("distributeV", "Vertikal verteilen"),
            ("-", ""),
            ("flipH", "Horizontal spiegeln"),
            ("flipV", "Vertikal spiegeln")
        ]
        for (key, title) in entries {
            if key == "-" {
                menu.addItem(.separator())
                continue
            }
            let entry = NSMenuItem(title: title, action: #selector(performAlignment(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = key
            menu.addItem(entry)
        }
        return menu
    }
}
