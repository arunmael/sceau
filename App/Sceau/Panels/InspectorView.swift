import AppKit
import ImageIO
import SwiftUI
import SceauCore

/// Das kontextabhängige Eigenschaften-Panel rechts im Dokumentfenster.
///
/// Zeigt je nach Auswahl unterschiedliche Inhalte: ohne Auswahl die
/// Zeichenflächen-Eigenschaften, bei genau einem Knoten dessen volle
/// Bearbeitung inklusive Formspezifika, bei mehreren nur die Aktionen, die
/// sich sinnvoll auf alle zusammen anwenden lassen.
@MainActor
struct InspectorView: View {
    let store: DocumentStore

    var body: some View {
        Form {
            switch store.selectedNodes.count {
            case 0:
                ArtboardInspector(store: store)
            case 1:
                SingleNodeInspector(store: store, node: store.selectedNodes[0])
            default:
                MultiNodeInspector(store: store, nodes: store.selectedNodes)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Keine Auswahl: Zeichenfläche

private struct ArtboardInspector: View {
    let store: DocumentStore

    var body: some View {
        Section("Zeichenfläche") {
            LabeledContent("Breite") {
                TextField("Breite", value: widthBinding, format: .number)
                    .frame(width: 80)
            }
            LabeledContent("Höhe") {
                TextField("Höhe", value: heightBinding, format: .number)
                    .frame(width: 80)
            }
            ColorPicker("Hintergrund", selection: backgroundBinding, supportsOpacity: true)
        }

        Section("Vorgabegrössen") {
            ForEach(ArtboardPreset.all) { preset in
                Button {
                    apply(preset)
                } label: {
                    HStack {
                        Text(preset.name)
                        Spacer()
                        Text("\(Int(preset.size.width))×\(Int(preset.size.height))")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { Double(store.document.artboard.size.width) },
            set: { newValue in
                store.apply("Zeichenflächenbreite ändern") { $0.artboard.size.width = max(1, CGFloat(newValue)) }
            }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { Double(store.document.artboard.size.height) },
            set: { newValue in
                store.apply("Zeichenflächenhöhe ändern") { $0.artboard.size.height = max(1, CGFloat(newValue)) }
            }
        )
    }

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { Color(rgba: store.document.artboard.background) },
            set: { newColor in
                store.apply("Hintergrundfarbe ändern") { $0.artboard.background = RGBAColor(color: newColor) }
            }
        )
    }

    private func apply(_ preset: ArtboardPreset) {
        store.apply("Zeichenflächengrösse ändern") { $0.artboard.size = preset.size }
    }
}

// MARK: - Genau ein Knoten ausgewählt

private struct SingleNodeInspector: View {
    let store: DocumentStore
    let node: Node

    var body: some View {
        positionSection

        if case let .shape(spec) = node.content {
            shapeSpecificSection(spec)
        }
        if case let .text(spec) = node.content {
            TextSection(store: store, node: node, spec: spec)
        }

        FillSection(nodes: [node], store: store)
        StrokeSection(nodes: [node], store: store)
        ShadowSection(nodes: [node], store: store)
        OpacitySection(nodes: [node], store: store)
    }

    // MARK: Position & Grösse
    //
    // Editiert wird über den aufgelösten, rotierten Hüllrahmen aus
    // ``NodeGeometry`` und dessen Abbildung über ``NodeTransform`` — dasselbe
    // Vorgehen, das auch das Ziehen der Canvas-Griffe verwendet, damit beide
    // Wege zum selben Ergebnis kommen.

    private var bounds: CGRect { NodeGeometry.bounds(for: node) }

    private var positionSection: some View {
        Section("Position & Grösse") {
            LabeledContent("X") { TextField("X", value: xBinding, format: .number).frame(width: 70) }
            LabeledContent("Y") { TextField("Y", value: yBinding, format: .number).frame(width: 70) }
            LabeledContent("Breite") { TextField("Breite", value: widthBinding, format: .number).frame(width: 70) }
            LabeledContent("Höhe") { TextField("Höhe", value: heightBinding, format: .number).frame(width: 70) }
            LabeledContent("Drehung") {
                HStack(spacing: 4) {
                    TextField("Drehung", value: rotationBinding, format: .number).frame(width: 60)
                    Text("°").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var xBinding: Binding<Double> {
        Binding(
            get: { Double(bounds.minX) },
            set: { newValue in
                let delta = CGVector(dx: CGFloat(newValue) - bounds.minX, dy: 0)
                applyNode("Position ändern") { $0 = NodeTransform.moved($0, by: delta) }
            }
        )
    }

    private var yBinding: Binding<Double> {
        Binding(
            get: { Double(bounds.minY) },
            set: { newValue in
                let delta = CGVector(dx: 0, dy: CGFloat(newValue) - bounds.minY)
                applyNode("Position ändern") { $0 = NodeTransform.moved($0, by: delta) }
            }
        )
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { Double(bounds.width) },
            set: { newValue in
                let target = CGRect(x: bounds.minX, y: bounds.minY, width: max(1, CGFloat(newValue)), height: bounds.height)
                applyNode("Breite ändern") { $0 = NodeTransform.resized($0, from: bounds, to: target) }
            }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { Double(bounds.height) },
            set: { newValue in
                let target = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(1, CGFloat(newValue)))
                applyNode("Höhe ändern") { $0 = NodeTransform.resized($0, from: bounds, to: target) }
            }
        )
    }

    private var rotationBinding: Binding<Double> {
        Binding(
            get: { Double(node.rotation * 180 / .pi) },
            set: { newValue in
                applyNode("Drehung ändern") { $0.rotation = CGFloat(newValue) * .pi / 180 }
            }
        )
    }

    // MARK: Formspezifisch

    @ViewBuilder
    private func shapeSpecificSection(_ spec: ShapeSpec) -> some View {
        switch spec {
        case let .rectangle(frame, cornerRadius):
            let maxRadius = max(1, min(frame.width, frame.height) / 2)
            Section("Rechteck") {
                LabeledContent("Eckradius") {
                    Slider(
                        value: cornerRadiusBinding(current: cornerRadius, max: maxRadius),
                        in: 0...maxRadius,
                        onEditingChanged: { editing in
                            if editing {
                                store.beginCoalescing("Eckradius ändern")
                            } else {
                                store.endCoalescing()
                            }
                        }
                    )
                    TextField("Eckradius", value: cornerRadiusBinding(current: cornerRadius, max: maxRadius), format: .number)
                        .frame(width: 50)
                }
            }

        case let .polygon(_, sides):
            Section("Polygon") {
                Stepper("Ecken: \(sides)", value: sidesBinding(current: sides), in: 3...24)
            }

        case let .star(_, points, innerRatio):
            Section("Stern") {
                Stepper("Zacken: \(points)", value: pointsBinding(current: points), in: 3...24)
                LabeledContent("Zackentiefe") {
                    Slider(
                        value: innerRatioBinding(current: innerRatio),
                        in: 0.05...0.95,
                        onEditingChanged: { editing in
                            if editing {
                                store.beginCoalescing("Zackentiefe ändern")
                            } else {
                                store.endCoalescing()
                            }
                        }
                    )
                }
            }

        case let .arrow(_, shaftRatio):
            Section("Pfeil") {
                LabeledContent("Schaftbreite") {
                    Slider(
                        value: shaftRatioBinding(current: shaftRatio),
                        in: 0.05...0.95,
                        onEditingChanged: { editing in
                            if editing {
                                store.beginCoalescing("Schaftbreite ändern")
                            } else {
                                store.endCoalescing()
                            }
                        }
                    )
                }
            }

        case let .speechBubble(frame, cornerRadius):
            let maxRadius = max(1, min(frame.width, frame.height) / 2)
            Section("Sprechblase") {
                LabeledContent("Eckradius") {
                    Slider(
                        value: bubbleCornerRadiusBinding(current: cornerRadius, max: maxRadius),
                        in: 0...maxRadius,
                        onEditingChanged: { editing in
                            if editing {
                                store.beginCoalescing("Eckradius ändern")
                            } else {
                                store.endCoalescing()
                            }
                        }
                    )
                }
            }

        case let .cross(_, armRatio):
            Section("Kreuz") {
                LabeledContent("Balkendicke") {
                    Slider(
                        value: armRatioBinding(current: armRatio),
                        in: 0.05...0.95,
                        onEditingChanged: { editing in
                            if editing {
                                store.beginCoalescing("Balkendicke ändern")
                            } else {
                                store.endCoalescing()
                            }
                        }
                    )
                }
            }

        case .ellipse, .squircle, .heart:
            EmptyView()
        }
    }

    private func shaftRatioBinding(current: CGFloat) -> Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { newValue in
                updateShape("Schaftbreite ändern") { spec in
                    if case let .arrow(frame, _) = spec {
                        spec = .arrow(frame: frame, shaftRatio: CGFloat(newValue))
                    }
                }
            }
        )
    }

    private func bubbleCornerRadiusBinding(current: CGFloat, max maxRadius: CGFloat) -> Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { newValue in
                updateShape("Eckradius ändern") { spec in
                    if case let .speechBubble(frame, _) = spec {
                        spec = .speechBubble(frame: frame, cornerRadius: min(maxRadius, max(0, CGFloat(newValue))))
                    }
                }
            }
        )
    }

    private func armRatioBinding(current: CGFloat) -> Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { newValue in
                updateShape("Balkendicke ändern") { spec in
                    if case let .cross(frame, _) = spec {
                        spec = .cross(frame: frame, armRatio: CGFloat(newValue))
                    }
                }
            }
        )
    }

    private func cornerRadiusBinding(current: CGFloat, max maxRadius: CGFloat) -> Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { newValue in
                updateShape("Eckradius ändern") { spec in
                    if case let .rectangle(frame, _) = spec {
                        spec = .rectangle(frame: frame, cornerRadius: min(maxRadius, max(0, CGFloat(newValue))))
                    }
                }
            }
        )
    }

    private func sidesBinding(current: Int) -> Binding<Int> {
        Binding(
            get: { current },
            set: { newValue in
                updateShape("Eckenzahl ändern") { spec in
                    if case let .polygon(frame, _) = spec {
                        spec = .polygon(frame: frame, sides: newValue)
                    }
                }
            }
        )
    }

    private func pointsBinding(current: Int) -> Binding<Int> {
        Binding(
            get: { current },
            set: { newValue in
                updateShape("Zackenzahl ändern") { spec in
                    if case let .star(frame, _, innerRatio) = spec {
                        spec = .star(frame: frame, points: newValue, innerRatio: innerRatio)
                    }
                }
            }
        )
    }

    private func innerRatioBinding(current: CGFloat) -> Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { newValue in
                updateShape("Zackentiefe ändern") { spec in
                    if case let .star(frame, points, _) = spec {
                        spec = .star(frame: frame, points: points, innerRatio: CGFloat(newValue))
                    }
                }
            }
        )
    }

    // MARK: Änderungen schreiben

    private func applyNode(_ actionName: String, _ update: (inout Node) -> Void) {
        var updated = node
        update(&updated)
        guard updated != node else { return }
        store.apply(actionName) { $0.replace(updated) }
    }

    private func updateShape(_ actionName: String, _ update: (inout ShapeSpec) -> Void) {
        guard case var .shape(spec) = node.content else { return }
        update(&spec)
        applyNode(actionName) { $0.content = .shape(spec) }
    }
}

// MARK: - Textknoten

private struct TextSection: View {
    let store: DocumentStore
    let node: Node
    let spec: TextSpec

    var body: some View {
        Section("Text") {
            // Mehrzeilig, damit auch eine zweizeilige Wortmarke eingebbar
            // bleibt; Absatzformatierung bleibt aussen vor.
            TextField("Text", text: stringBinding, axis: .vertical)
                .lineLimit(1...4)
        }

        Section("Schrift") {
            LabeledContent("Schrift") { TextField("Schrift", text: fontNameBinding) }
            LabeledContent("Grösse") { TextField("Grösse", value: fontSizeBinding, format: .number).frame(width: 60) }
            LabeledContent("Zeichenabstand") { TextField("Zeichenabstand", value: trackingBinding, format: .number).frame(width: 60) }
            LabeledContent("Wortabstand") { TextField("Wortabstand", value: wordSpacingBinding, format: .number).frame(width: 60) }
        }
    }

    private func update(_ actionName: String, _ mutate: (inout TextSpec) -> Void) {
        var updatedSpec = spec
        mutate(&updatedSpec)
        var updatedNode = node
        updatedNode.content = .text(updatedSpec)
        guard updatedNode != node else { return }
        store.apply(actionName) { $0.replace(updatedNode) }
    }

    private var stringBinding: Binding<String> {
        Binding(get: { spec.string }, set: { newValue in update("Text ändern") { $0.string = newValue } })
    }

    private var fontNameBinding: Binding<String> {
        Binding(get: { spec.fontName }, set: { newValue in update("Schrift ändern") { $0.fontName = newValue } })
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(spec.fontSize) },
            set: { newValue in update("Schriftgrösse ändern") { $0.fontSize = max(1, CGFloat(newValue)) } }
        )
    }

    private var trackingBinding: Binding<Double> {
        Binding(
            get: { Double(spec.tracking) },
            set: { newValue in update("Zeichenabstand ändern") { $0.tracking = CGFloat(newValue) } }
        )
    }

    private var wordSpacingBinding: Binding<Double> {
        Binding(
            get: { Double(spec.wordSpacing) },
            set: { newValue in update("Wortabstand ändern") { $0.wordSpacing = CGFloat(newValue) } }
        )
    }
}

// MARK: - Mehrfachauswahl

private struct MultiNodeInspector: View {
    let store: DocumentStore
    let nodes: [Node]

    var body: some View {
        Section {
            Text("\(nodes.count) Objekte ausgewählt")
                .foregroundStyle(.secondary)
        }

        FillSection(nodes: nodes, store: store)
        StrokeSection(nodes: nodes, store: store)
        ShadowSection(nodes: nodes, store: store)
        OpacitySection(nodes: nodes, store: store)
    }
}

// MARK: - Fläche (einzeln wie mehrfach)

private struct FillSection: View {
    let nodes: [Node]
    let store: DocumentStore

    private var current: Paint? { commonValue(of: nodes, \.style.fill) }

    var body: some View {
        Section("Fläche") {
            Picker("Art", selection: kindBinding) {
                if current == nil {
                    Text("Gemischt").tag(FillKind.mixed)
                }
                Text("Keine").tag(FillKind.none)
                Text("Vollton").tag(FillKind.solid)
                Text("Linearer Verlauf").tag(FillKind.linear)
                Text("Radialer Verlauf").tag(FillKind.radial)
                Text("Muster").tag(FillKind.pattern)
            }

            if let current {
                switch current {
                case .none:
                    EmptyView()
                case let .solid(color):
                    solidControls(color)
                case let .linearGradient(gradient), let .radialGradient(gradient):
                    GradientStopsEditor(gradient: gradient, store: store) { updated in
                        apply(makePaint(likeCurrent: current, gradient: updated))
                    }
                case let .pattern(fill):
                    PatternControls(fill: fill) { apply(.pattern($0)) }
                }
            }
        }
    }

    @ViewBuilder
    private func solidControls(_ color: RGBAColor) -> some View {
        ColorPicker(
            "Farbe",
            selection: Binding(
                get: { Color(rgba: color) },
                set: { apply(.solid(RGBAColor(color: $0))) }
            ),
            supportsOpacity: true
        )
        LabeledContent("Hex") {
            HexColorField(hex: color.hexString) { apply(.solid($0)) }
        }
    }

    private var kindBinding: Binding<FillKind> {
        Binding(
            get: { FillKind(current) },
            set: { newKind in
                guard newKind != .mixed else { return }
                apply(newKind.makePaint(from: current))
            }
        )
    }

    private func makePaint(likeCurrent current: Paint, gradient: SceauCore.Gradient) -> Paint {
        if case .radialGradient = current { return .radialGradient(gradient) }
        return .linearGradient(gradient)
    }

    private func apply(_ paint: Paint) {
        store.apply("Fläche ändern") { document in
            for node in nodes {
                guard var updated = document.node(id: node.id) else { continue }
                updated.style.fill = paint
                document.replace(updated)
            }
        }
    }
}

private enum FillKind: Hashable {
    case none, solid, linear, radial, pattern, mixed

    init(_ paint: Paint?) {
        guard let paint else { self = .mixed; return }
        switch paint {
        case .none: self = .none
        case .solid: self = .solid
        case .linearGradient: self = .linear
        case .radialGradient: self = .radial
        case .pattern: self = .pattern
        }
    }

    func makePaint(from current: Paint?) -> Paint {
        switch self {
        case .none:
            return .none
        case .solid:
            if case let .solid(color) = current { return .solid(color) }
            return .solid(RGBAColor(red: 0.35, green: 0.42, blue: 0.95))
        case .linear:
            if case let .linearGradient(gradient) = current { return .linearGradient(gradient) }
            return .linearGradient(Self.defaultGradient)
        case .radial:
            if case let .radialGradient(gradient) = current { return .radialGradient(gradient) }
            return .radialGradient(Self.defaultGradient)
        case .pattern:
            if case let .pattern(fill) = current { return .pattern(fill) }
            return .pattern(Self.defaultPattern)
        case .mixed:
            return current ?? .none
        }
    }

    private static let defaultGradient = SceauCore.Gradient(
        stops: [
            GradientStop(color: .white, location: 0),
            GradientStop(color: .black, location: 1)
        ],
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 1, y: 1)
    )

    /// Ein 1×1-Platzhalterbild, bis der Nutzer über den Bild-Wähler eine
    /// eigene Kachel setzt — ein Muster ganz ohne Bild wäre unsichtbar und
    /// liesse den frisch gewählten Picker-Eintrag wirkungslos aussehen.
    private static let defaultPattern = PatternFill(
        imageData: placeholderPatternImageData,
        tileSize: CGSize(width: 32, height: 32)
    )
}

/// Ein einzelnes graues 1×1-PNG als Platzhalterkachel. Bewusst eine freie
/// Konstante ausserhalb jeder `View` — sonst zieht die Isolationsprüfung des
/// Compilers hier fälschlich `@MainActor` heran, obwohl reines Core-Graphics-
/// und ImageIO-Zeichnen keinerlei UI-Zustand anfasst.
private let placeholderPatternImageData: Data = {
    let space = CGColorSpaceCreateDeviceRGB()
    var pixel: [UInt8] = [180, 180, 180, 255]
    return pixel.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(
            data: bytes.baseAddress, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), let image = context.makeImage() else { return Data() }
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return mutableData as Data
    }
}()

// MARK: - Muster

private struct PatternControls: View {
    let fill: PatternFill
    let onChange: (PatternFill) -> Void

    var body: some View {
        LabeledContent("Bild") {
            Button("Bild wählen…") { chooseImage() }
        }
        LabeledContent("Kachelgrösse") {
            HStack(spacing: 4) {
                TextField("Breite", value: widthBinding, format: .number).frame(width: 50)
                Text("×")
                TextField("Höhe", value: heightBinding, format: .number).frame(width: 50)
            }
        }
        LabeledContent("Drehung") {
            Slider(value: rotationBinding, in: 0...360)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url)
        else { return }
        var updated = fill
        updated.imageData = data
        onChange(updated)
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { Double(fill.tileSize.width) },
            set: { var f = fill; f.tileSize.width = max(1, CGFloat($0)); onChange(f) }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { Double(fill.tileSize.height) },
            set: { var f = fill; f.tileSize.height = max(1, CGFloat($0)); onChange(f) }
        )
    }

    private var rotationBinding: Binding<Double> {
        Binding(
            get: { Double(fill.rotation * 180 / .pi) },
            set: { var f = fill; f.rotation = CGFloat($0) * .pi / 180; onChange(f) }
        )
    }
}

/// Editierbare Farbstopps eines Verlaufs — Start-/Endpunkt bleiben fix auf der
/// Diagonale, weil nur die Stopps selbst laut Funktionsumfang bearbeitbar sein
/// müssen.
private struct GradientStopsEditor: View {
    let gradient: SceauCore.Gradient
    let store: DocumentStore
    let onChange: (SceauCore.Gradient) -> Void

    var body: some View {
        ForEach(gradient.stops.indices, id: \.self) { index in
            HStack {
                ColorPicker("", selection: colorBinding(index), supportsOpacity: true)
                    .labelsHidden()

                Slider(
                    value: locationBinding(index),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if editing {
                            store.beginCoalescing("Verlauf ändern")
                        } else {
                            store.endCoalescing()
                        }
                    }
                )

                Text("\(Int((stop(index)?.location ?? 0) * 100)) %")
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                if gradient.stops.count > 2 {
                    Button(role: .destructive) { removeStop(index) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if gradient.stops.count < 3 {
            Button("Farbstopp hinzufügen", action: addStop)
        }
    }

    /// Zugriff auf einen Farbstopp, der einen veralteten Index verträgt.
    ///
    /// `ForEach` über `indices` behält nach dem Entfernen eines Stopps kurz die
    /// alte Indexmenge, und SwiftUI wertet die Bindings der verschwundenen Zeile
    /// noch einmal aus. Ein direkter Indexzugriff stürzt dabei ab — deshalb
    /// laufen sämtliche Zugriffe über diese Prüfung.
    private func stop(_ index: Int) -> GradientStop? {
        gradient.stops.indices.contains(index) ? gradient.stops[index] : nil
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { Color(rgba: stop(index)?.color ?? .black) },
            set: { newColor in
                guard gradient.stops.indices.contains(index) else { return }
                var updated = gradient
                updated.stops[index].color = RGBAColor(color: newColor)
                onChange(updated)
            }
        )
    }

    private func locationBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { Double(stop(index)?.location ?? 0) },
            set: { newValue in
                guard gradient.stops.indices.contains(index) else { return }
                var updated = gradient
                updated.stops[index].location = CGFloat(newValue)
                onChange(updated)
            }
        )
    }

    private func addStop() {
        var updated = gradient
        updated.stops.append(GradientStop(color: .black, location: 1))
        onChange(updated)
    }

    private func removeStop(_ index: Int) {
        guard gradient.stops.indices.contains(index), gradient.stops.count > 2 else { return }
        var updated = gradient
        updated.stops.remove(at: index)
        onChange(updated)
    }
}

// MARK: - Kontur (einzeln wie mehrfach)

private struct StrokeSection: View {
    let nodes: [Node]
    let store: DocumentStore

    /// Äusseres Optional: uneinheitlich in der Auswahl. Inneres Optional: Kontur an/aus.
    private var current: Stroke?? { commonValue(of: nodes, \.style.stroke) }

    var body: some View {
        Section("Kontur") {
            if let current {
                Toggle("Kontur", isOn: Binding(
                    get: { current != nil },
                    set: { isOn in apply(isOn ? (current ?? Stroke()) : nil) }
                ))

                if let stroke = current {
                    ColorPicker(
                        "Farbe",
                        selection: Binding(
                            get: { Color(rgba: strokeColor(stroke)) },
                            set: { newColor in
                                var updated = stroke
                                updated.paint = .solid(RGBAColor(color: newColor))
                                apply(updated)
                            }
                        ),
                        supportsOpacity: true
                    )

                    LabeledContent("Stärke") {
                        TextField(
                            "Stärke",
                            value: Binding(
                                get: { Double(stroke.width) },
                                set: { newValue in
                                    var updated = stroke
                                    updated.width = max(0, CGFloat(newValue))
                                    apply(updated)
                                }
                            ),
                            format: .number
                        )
                        .frame(width: 50)
                    }

                    Picker(
                        "Enden",
                        selection: Binding(
                            get: { stroke.cap },
                            set: { newValue in
                                var updated = stroke
                                updated.cap = newValue
                                apply(updated)
                            }
                        )
                    ) {
                        ForEach(StrokeCap.allCases, id: \.self) { cap in
                            Text(capTitle(cap)).tag(cap)
                        }
                    }

                    Picker(
                        "Ecken",
                        selection: Binding(
                            get: { stroke.join },
                            set: { newValue in
                                var updated = stroke
                                updated.join = newValue
                                apply(updated)
                            }
                        )
                    ) {
                        ForEach(StrokeJoin.allCases, id: \.self) { join in
                            Text(joinTitle(join)).tag(join)
                        }
                    }

                    Toggle(
                        "Gestrichelt",
                        isOn: Binding(
                            get: { !stroke.dash.isEmpty },
                            set: { dashed in
                                var updated = stroke
                                updated.dash = dashed ? [updated.width * 2, updated.width * 2] : []
                                apply(updated)
                            }
                        )
                    )
                }
            } else {
                LabeledContent("Kontur") {
                    Text("Gemischt").foregroundStyle(.secondary)
                }
                Button("Kontur hinzufügen") { apply(Stroke()) }
            }
        }
    }

    private func strokeColor(_ stroke: Stroke) -> RGBAColor {
        if case let .solid(color) = stroke.paint { return color }
        return .black
    }

    private func capTitle(_ cap: StrokeCap) -> String {
        switch cap {
        case .butt: return "Gerade"
        case .round: return "Rund"
        case .square: return "Quadratisch"
        }
    }

    private func joinTitle(_ join: StrokeJoin) -> String {
        switch join {
        case .miter: return "Spitz"
        case .round: return "Rund"
        case .bevel: return "Abgeflacht"
        }
    }

    private func apply(_ stroke: Stroke?) {
        store.apply("Kontur ändern") { document in
            for node in nodes {
                guard var updated = document.node(id: node.id) else { continue }
                updated.style.stroke = stroke
                document.replace(updated)
            }
        }
    }
}

// MARK: - Schlagschatten (einzeln wie mehrfach)

private struct ShadowSection: View {
    let nodes: [Node]
    let store: DocumentStore

    /// Äusseres Optional: uneinheitlich in der Auswahl. Inneres Optional: Schatten an/aus.
    private var current: Shadow?? { commonValue(of: nodes, \.style.shadow) }

    var body: some View {
        Section("Schatten") {
            if let current {
                Toggle("Schlagschatten", isOn: Binding(
                    get: { current != nil },
                    set: { isOn in apply(isOn ? (current ?? Shadow()) : nil) }
                ))

                if let shadow = current {
                    ColorPicker(
                        "Farbe",
                        selection: Binding(
                            get: { Color(rgba: shadow.color) },
                            set: { newColor in
                                var updated = shadow
                                updated.color = RGBAColor(color: newColor)
                                apply(updated)
                            }
                        ),
                        supportsOpacity: true
                    )

                    LabeledContent("Versatz") {
                        HStack(spacing: 4) {
                            TextField("X", value: Binding(
                                get: { Double(shadow.offset.width) },
                                set: { var updated = shadow; updated.offset.width = CGFloat($0); apply(updated) }
                            ), format: .number).frame(width: 50)
                            Text("×")
                            TextField("Y", value: Binding(
                                get: { Double(shadow.offset.height) },
                                set: { var updated = shadow; updated.offset.height = CGFloat($0); apply(updated) }
                            ), format: .number).frame(width: 50)
                        }
                    }

                    LabeledContent("Weichzeichnung") {
                        Slider(
                            value: Binding(
                                get: { Double(shadow.blurRadius) },
                                set: { var updated = shadow; updated.blurRadius = max(0, CGFloat($0)); apply(updated) }
                            ),
                            in: 0...50,
                            onEditingChanged: { editing in
                                if editing {
                                    store.beginCoalescing("Weichzeichnung ändern")
                                } else {
                                    store.endCoalescing()
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private func apply(_ shadow: Shadow?) {
        store.apply("Schatten ändern") { document in
            for node in nodes {
                guard var updated = document.node(id: node.id) else { continue }
                updated.style.shadow = shadow
                document.replace(updated)
            }
        }
    }
}

// MARK: - Deckkraft (einzeln wie mehrfach)

private struct OpacitySection: View {
    let nodes: [Node]
    let store: DocumentStore

    private var current: CGFloat? { commonValue(of: nodes, \.style.opacity) }

    var body: some View {
        Section("Deckkraft") {
            Slider(
                value: binding,
                in: 0...1,
                onEditingChanged: { editing in
                    if editing {
                        store.beginCoalescing("Deckkraft ändern")
                    } else {
                        store.endCoalescing()
                    }
                }
            )
            if current == nil {
                Text("Gemischt").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var binding: Binding<Double> {
        Binding(
            get: { Double(current ?? 1) },
            set: { newValue in
                store.apply("Deckkraft ändern") { document in
                    for node in nodes {
                        guard var updated = document.node(id: node.id) else { continue }
                        updated.style.opacity = CGFloat(newValue)
                        document.replace(updated)
                    }
                }
            }
        )
    }
}

// MARK: - Gemeinsamer Wert einer Auswahl

/// `nil`, wenn die Auswahl an dieser Eigenschaft nicht einheitlich ist —
/// Grundlage dafür, bei Mehrfachauswahl keine widersprüchlichen Einzelwerte
/// vorzutäuschen.
private func commonValue<T: Equatable>(of nodes: [Node], _ keyPath: KeyPath<Node, T>) -> T? {
    guard let first = nodes.first?[keyPath: keyPath] else { return nil }
    return nodes.allSatisfy { $0[keyPath: keyPath] == first } ? first : nil
}

// MARK: - Hex-Eingabefeld

/// Eigener kleiner State, damit während des Tippens nicht bei jedem
/// Zwischenstand (noch kein gültiges Hex) der Text vom Modellwert
/// überschrieben wird. Synchronisiert nur, solange das Feld nicht fokussiert ist.
private struct HexColorField: View {
    let hex: String
    let onCommit: (RGBAColor) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(hex: String, onCommit: @escaping (RGBAColor) -> Void) {
        self.hex = hex
        self.onCommit = onCommit
        _text = State(initialValue: hex)
    }

    var body: some View {
        TextField("Hex", text: $text)
            .frame(width: 90)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onChange(of: hex) { _, newValue in
                if !isFocused { text = newValue }
            }
    }

    private func commit() {
        guard let color = RGBAColor(hex: text) else {
            text = hex
            return
        }
        onCommit(color)
    }
}

// MARK: - Farbumwandlung RGBAColor ↔ Color

private extension Color {
    /// Baut die SwiftUI-Farbe explizit im sRGB-Raum, damit Anzeige und der
    /// spätere SVG-/PDF-Export dieselben Werte sehen.
    init(rgba: RGBAColor) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

private extension RGBAColor {
    /// Liest die Komponenten einer SwiftUI-Farbe zurück — über `NSColor`, da
    /// `Color` seine Komponenten nicht direkt offenlegt. Ebenfalls explizit im
    /// sRGB-Raum aufgelöst.
    init(color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        self.init(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            alpha: Double(resolved.alphaComponent)
        )
    }

    var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
