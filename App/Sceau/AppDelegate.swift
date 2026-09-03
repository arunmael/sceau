import AppKit

/// Einstiegspunkt der App.
///
/// Die Menüleiste wird programmatisch aufgebaut statt aus einem NIB geladen:
/// Ohne NIB gibt es keine verborgene zweite Quelle der Wahrheit, und die
/// Einträge stehen zusammen mit ihren Aktionen an einer Stelle im Code.
@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Dokumentbasierte Apps bleiben ohne Fenster geöffnet — sonst wäre nach
        // dem Schliessen des letzten Dokuments kein „Neu" mehr erreichbar.
        false
    }
}

/// Baut die Menüleiste.
enum MainMenuBuilder {

    static func build() -> NSMenu {
        let root = NSMenu()
        root.addItem(makeSubmenu(appMenu(), title: "Sceau"))
        root.addItem(makeSubmenu(fileMenu(), title: "Ablage"))
        root.addItem(makeSubmenu(editMenu(), title: "Bearbeiten"))
        root.addItem(makeSubmenu(objectMenu(), title: "Objekt"))
        root.addItem(makeSubmenu(viewMenu(), title: "Darstellung"))
        root.addItem(makeSubmenu(windowMenu(), title: "Fenster"))
        return root
    }

    private static func makeSubmenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }

    /// Kurzschreibweise für einen Eintrag, der an den First Responder geht.
    ///
    /// `target = nil` bedeutet, dass AppKit den Eintrag durch die
    /// Responder-Kette schickt — dadurch beantwortet automatisch das gerade
    /// aktive Dokument bzw. Fenster den Befehl, ohne dass hier etwas verdrahtet
    /// werden müsste.
    private static func item(
        _ title: String,
        _ selector: Selector?,
        _ key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        representedObject: Any? = nil
    ) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        entry.representedObject = representedObject
        return entry
    }

    // MARK: - Menüs

    private static func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Über Sceau", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Sceau ausblenden", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Andere ausblenden", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]))
        menu.addItem(item("Alle einblenden", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Sceau beenden", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Neu", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("Öffnen …", #selector(NSDocumentController.openDocument(_:)), "o"))
        menu.addItem(.separator())
        menu.addItem(item("Schliessen", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Sichern", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Sichern unter …", #selector(NSDocument.saveAs(_:)), "s", modifiers: [.command, .shift]))
        // Ausdrücklicher Wiederherstellungspunkt vor riskanten Schritten —
        // die Anforderung aus Abschnitt 2.1 des Entwicklungsplans.
        menu.addItem(item("Version jetzt sichern", #selector(SceauDocument.saveVersionNow(_:)), "s", modifiers: [.command, .option]))
        menu.addItem(item("Alle Versionen durchsuchen …", #selector(NSDocument.browseVersions(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Zurück zur gesicherten Version", #selector(NSDocument.revertToSaved(_:))))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Widerrufen", Selector(("undo:")), "z"))
        menu.addItem(item("Wiederholen", Selector(("redo:")), "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Ausschneiden", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Kopieren", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Einsetzen", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Duplizieren", Selector(("duplicate:")), "d"))
        menu.addItem(item("Löschen", Selector(("delete:")), "\u{8}", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(item("Alles auswählen", #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private static func objectMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Gruppieren", #selector(DocumentWindowController.groupSelection(_:)), "g"))
        menu.addItem(item("Gruppierung auflösen", #selector(DocumentWindowController.ungroupSelection(_:)), "g", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Nach vorne", #selector(DocumentWindowController.bringForward(_:)), "]"))
        menu.addItem(item("Nach hinten", #selector(DocumentWindowController.sendBackward(_:)), "["))
        menu.addItem(.separator())

        let pathfinder = NSMenu(title: "Pathfinder")
        let operations: [(String, String, String)] = [
            ("Vereinigen", "union", "1"),
            ("Subtrahieren", "subtract", "2"),
            ("Schnittmenge", "intersect", "3"),
            ("Ausschliessen", "exclude", "4")
        ]
        for (title, key, shortcut) in operations {
            pathfinder.addItem(item(
                title,
                #selector(DocumentWindowController.performBooleanOperationFromMenu(_:)),
                shortcut,
                modifiers: [.command, .shift],
                representedObject: key
            ))
        }
        menu.addItem(makeSubmenu(pathfinder, title: "Pathfinder"))
        menu.addItem(.separator())
        menu.addItem(item(
            "Text in Pfade umwandeln",
            #selector(DocumentWindowController.convertTextToOutlines(_:)),
            "o",
            modifiers: [.command, .shift]
        ))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Vergrössern", #selector(DocumentWindowController.zoomIn(_:)), "+"))
        menu.addItem(item("Verkleinern", #selector(DocumentWindowController.zoomOut(_:)), "-"))
        menu.addItem(item("Originalgrösse", #selector(DocumentWindowController.zoomToFit(_:)), "0"))
        menu.addItem(.separator())
        menu.addItem(item("Raster einblenden", #selector(DocumentWindowController.toggleGrid(_:)), "'"))
        menu.addItem(item("Einrasten", #selector(DocumentWindowController.toggleSnapping(_:)), "'", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Vollbild", #selector(NSWindow.toggleFullScreen(_:)), "f", modifiers: [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Im Dock ablegen", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoomen", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Alle nach vorne bringen", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
