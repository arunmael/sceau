import AppKit
import SceauCore

/// Ausrichten, Verteilen und Spiegeln der Auswahl.
@MainActor
enum AlignmentCommands {

    static func perform(named key: String, on store: DocumentStore) {
        let selected = store.document.nodes(with: store.selection)
        guard !selected.isEmpty else { return }

        let boxes = selected.map { NodeGeometry.bounds(for: $0) }
        guard boxes.allSatisfy({ !$0.isNull }) else { return }

        switch key {
        case "left": align(selected, boxes, .left, store)
        case "centerX": align(selected, boxes, .centerX, store)
        case "right": align(selected, boxes, .right, store)
        case "top": align(selected, boxes, .top, store)
        case "centerY": align(selected, boxes, .centerY, store)
        case "bottom": align(selected, boxes, .bottom, store)
        case "distributeH": distribute(selected, boxes, .horizontal, store)
        case "distributeV": distribute(selected, boxes, .vertical, store)
        case "flipH": mirror(selected, boxes, .horizontal, store)
        case "flipV": mirror(selected, boxes, .vertical, store)
        default: break
        }
    }

    private static func align(
        _ nodes: [Node],
        _ boxes: [CGRect],
        _ edge: AlignmentEdge,
        _ store: DocumentStore
    ) {
        // Bei genau einem Objekt gibt es keine Auswahl, an der man ausrichten
        // könnte — dann ist die Zeichenfläche der sinnvolle Bezug.
        let container: CGRect? = nodes.count == 1 ? store.document.artboard.frame : nil
        let offsets = LayoutOps.align(boxes, to: edge, within: container)

        store.apply("Ausrichten") { document in
            for (node, offset) in zip(nodes, offsets) where offset != .zero {
                document.replace(NodeTransform.moved(node, by: offset))
            }
        }
    }

    private static func distribute(
        _ nodes: [Node],
        _ boxes: [CGRect],
        _ axis: Axis,
        _ store: DocumentStore
    ) {
        let offsets = LayoutOps.distribute(boxes, along: axis)
        store.apply("Verteilen") { document in
            for (node, offset) in zip(nodes, offsets) where offset != .zero {
                document.replace(NodeTransform.moved(node, by: offset))
            }
        }
    }

    private static func mirror(
        _ nodes: [Node],
        _ boxes: [CGRect],
        _ axis: Axis,
        _ store: DocumentStore
    ) {
        // Gespiegelt wird an der Mitte der gesamten Auswahl, damit mehrere
        // Objekte ihre Anordnung zueinander behalten und nicht jedes für sich
        // an Ort und Stelle kippt.
        let reference = LayoutOps.boundingBox(of: boxes)
        store.apply(axis == .horizontal ? "Horizontal spiegeln" : "Vertikal spiegeln") { document in
            for node in nodes {
                document.replace(NodeTransform.mirrored(node, along: axis, about: reference))
            }
        }
    }
}
