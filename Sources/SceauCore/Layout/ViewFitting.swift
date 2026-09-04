import CoreGraphics

public enum ViewFitting {
    /// Der Zoomfaktor, bei dem die Zeichenfläche vollständig in den sichtbaren
    /// Bereich passt.
    public static func zoomToFit(
        artboard: CGSize,
        in viewport: CGSize,
        padding: CGFloat = 40
    ) -> CGFloat {
        // Ungültige Geometrie darf sich nicht als NaN oder Unendlich bis in die
        // Darstellung fortpflanzen, weil die Ansicht dann nicht mehr bedienbar wäre.
        guard artboard.width.isFinite, artboard.width > 0,
              artboard.height.isFinite, artboard.height > 0,
              viewport.width.isFinite, viewport.width > 0,
              viewport.height.isFinite, viewport.height > 0,
              padding.isFinite, padding >= 0
        else { return 1 }

        let usableWidth = viewport.width - 2 * padding
        let usableHeight = viewport.height - 2 * padding
        guard usableWidth.isFinite, usableWidth > 0,
              usableHeight.isFinite, usableHeight > 0
        else { return 1 }

        let zoom = min(usableWidth / artboard.width, usableHeight / artboard.height)
        guard zoom.isFinite, zoom > 0 else { return 1 }
        return min(64, max(0.05, zoom))
    }
}
