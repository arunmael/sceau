import CoreGraphics
import Foundation

/// Ein eingebettetes Rasterbild.
///
/// Aus missing.md ("Hintergrund von Bild entfernen?"): Sceau berechnet die
/// Freistellung bewusst **nicht** selbst — macOS bringt das bereits als
/// Systemfunktion mit (z. B. "Motiv kopieren" in Vorschau/Fotos/Finder). Ein
/// Nutzer bereitet ein Bild dort vor und bringt es fertig freigestellt
/// (transparentes PNG) hierher; Sceau muss dafür nur überhaupt ein Bild als
/// Objekt platzieren können.
///
/// Bewusst **kein** eigener Bild-Bearbeitungsfunktionsumfang (Filter,
/// Zuschneiden, Freistellen) — nur Platzieren, Verschieben, Skalieren, wie
/// jedes andere Objekt auch. Die Bilddaten liegen direkt im Dokument
/// (wie bei ``PatternFill``), damit eine `.sceau`-Datei in sich
/// abgeschlossen bleibt.
public struct ImageSpec: Equatable, Sendable, Codable {
    /// Kodierte Bilddaten (PNG oder JPEG).
    public var data: Data
    /// Rahmen in Dokumentpunkten, in den das Bild eingepasst wird.
    public var frame: CGRect

    public init(data: Data, frame: CGRect) {
        self.data = data
        self.frame = frame
    }
}
