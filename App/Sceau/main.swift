import AppKit

// Der Programmstart wird ausdrücklich aufgesetzt statt über `@main`.
//
// Mit `@main` auf dem Delegate wurde dieser erst gesetzt, nachdem AppKit die
// Start-Benachrichtigungen bereits verschickt hatte: Weder
// `applicationWillFinishLaunching` noch `applicationDidFinishLaunching`
// erreichten ihn. In der Folge blieb die Menüleiste bei dem, was AppKit von
// sich aus anlegt — nur Apple- und Programmmenü —, und die Absturzerfassung
// wurde nie gestartet. Beides fällt beim Ausprobieren kaum auf und wiegt
// schwer.
//
// Hier steht die Reihenfolge fest: Delegate setzen, Menüleiste einhängen,
// erst dann laufen lassen.

let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
application.mainMenu = MainMenuBuilder.build()
application.setActivationPolicy(.regular)
application.run()
