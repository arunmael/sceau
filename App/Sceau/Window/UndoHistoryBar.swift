import AppKit
import SceauCore

/// Die schwebende Verlaufspille unten auf der Zeichenfläche.
///
/// Eingeklappt zeigt sie nur Widerrufen, Verlauf und Wiederholen; ausgeklappt
/// die Zeitachse, über die sich mit einem Zug ein früherer Stand ansteuern
/// lässt. Bewusst nicht in der Werkzeugleiste: Dort gilt weiterhin die Grenze
/// von sieben sichtbaren Bedienelementen aus dem Entwicklungsplan, und der
/// Verlauf gehört ohnehin näher an das Bild als an die Werkzeuge.
///
/// ⌘Z und ⇧⌘Z laufen unverändert über die Menüleiste; diese Pille ist die
/// *sichtbare* Entsprechung dazu, keine zweite Wahrheit.
@MainActor
final class UndoHistoryBar: NSView {

    private let store: DocumentStore

    private let undoButton: NSButton
    private let redoButton: NSButton
    private let timeline = UndoTimelineView()

    private var collapsedRow: NSStackView?
    private var expandedRow: NSStackView?
    private var isExpanded = false

    init(store: DocumentStore) {
        self.store = store
        undoButton = Self.iconButton(symbol: "arrow.uturn.backward", tooltip: "Widerrufen (⌘Z)")
        redoButton = Self.iconButton(symbol: "arrow.uturn.forward", tooltip: "Wiederholen (⇧⌘Z)")
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        buildContents()
        undoButton.target = self
        undoButton.action = #selector(undo(_:))
        redoButton.target = self
        redoButton.action = #selector(redo(_:))

        timeline.onSelectDepth = { [weak self] depth in
            self?.store.jump(toDepth: depth)
        }

        observeStore()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Nur programmatisch verwendet") }

    // MARK: - Aufbau

    private static func iconButton(symbol: String, tooltip: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .smallSquare
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private func buildContents() {
        let expand = Self.iconButton(symbol: "clock.arrow.circlepath", tooltip: "Verlauf einblenden")
        expand.target = self
        expand.action = #selector(toggleTimeline(_:))

        let collapse = Self.iconButton(symbol: "clock.arrow.circlepath", tooltip: "Verlauf ausblenden")
        collapse.target = self
        collapse.action = #selector(toggleTimeline(_:))
        collapse.contentTintColor = .controlAccentColor

        timeline.translatesAutoresizingMaskIntoConstraints = false
        timeline.widthAnchor.constraint(equalToConstant: 160).isActive = true
        timeline.heightAnchor.constraint(equalToConstant: 28).isActive = true
        timeline.toolTip = "Verlauf — ziehen, um zu einem früheren Schritt zurückzugehen"

        let collapsed = NSStackView(views: [undoButton, expand, redoButton])
        collapsed.orientation = .horizontal
        collapsed.alignment = .centerY
        collapsed.spacing = 12
        collapsed.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)

        let expanded = NSStackView(views: [timeline, collapse])
        expanded.orientation = .horizontal
        expanded.alignment = .centerY
        expanded.spacing = 12
        expanded.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        expanded.isHidden = true

        // Beide Zustände bleiben Teil derselben Ansicht: `NSStackView` nimmt
        // die ausgeblendete Zeile aus seiner Grösse heraus, sodass die Pille
        // beim Umschalten ohne Neuaufbau mitwächst.
        let rows = NSStackView(views: [collapsed, expanded])
        rows.orientation = .vertical
        rows.alignment = .centerX
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        collapsedRow = collapsed
        expandedRow = expanded

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 15
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        background.translatesAutoresizingMaskIntoConstraints = false

        addSubview(background)
        addSubview(rows)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
    }

    // MARK: - Zustand

    /// `withObservationTracking` meldet nur **eine** Änderung, deshalb wird die
    /// Beobachtung im Änderungsfall sofort neu aufgesetzt — dasselbe Muster wie
    /// in ``CanvasView``.
    private func observeStore() {
        withObservationTracking {
            _ = store.undoDepth
            _ = store.redoDepth
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                self.observeStore()
            }
        }
    }

    private func refresh() {
        timeline.setDepths(undo: store.undoDepth, redo: store.redoDepth)
        undoButton.isEnabled = store.undoManager?.canUndo ?? false
        redoButton.isEnabled = store.undoManager?.canRedo ?? false
    }

    // MARK: - Befehle

    @objc private func toggleTimeline(_ sender: Any?) {
        isExpanded.toggle()
        collapsedRow?.isHidden = isExpanded
        expandedRow?.isHidden = !isExpanded
    }

    @objc private func undo(_ sender: Any?) {
        store.undoManager?.undo()
        refresh()
    }

    @objc private func redo(_ sender: Any?) {
        store.undoManager?.redo()
        refresh()
    }
}
