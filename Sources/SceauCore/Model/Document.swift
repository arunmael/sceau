import CoreGraphics
import Foundation

/// Die Zeichenfläche eines Dokuments.
///
/// Genau eine pro Dokument — ein Multi-Artboard-System ist laut
/// Entwicklungsplan bewusst nicht Teil von v1.
public struct Artboard: Equatable, Sendable, Codable {
    public var size: CGSize
    /// Hintergrundfarbe. `.clear` bedeutet transparent — der Normalfall für
    /// Logos und Icons.
    public var background: RGBAColor

    public init(size: CGSize, background: RGBAColor = .clear) {
        self.size = size
        self.background = background
    }

    /// Ursprung liegt bei (0,0); der Rahmen spannt sich über die volle Fläche.
    public var frame: CGRect {
        CGRect(origin: .zero, size: size)
    }
}

/// Eine benannte Vorgabegrösse für neue Dokumente.
public struct ArtboardPreset: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let size: CGSize

    public init(name: String, size: CGSize) {
        self.name = name
        self.size = size
    }

    public static let appIcon = ArtboardPreset(name: "App-Icon", size: CGSize(width: 1024, height: 1024))
    public static let favicon = ArtboardPreset(name: "Favicon", size: CGSize(width: 64, height: 64))
    public static let socialProfile = ArtboardPreset(name: "Profilbild", size: CGSize(width: 512, height: 512))
    public static let square = ArtboardPreset(name: "Quadrat 512", size: CGSize(width: 512, height: 512))

    public static let all: [ArtboardPreset] = [.appIcon, .socialProfile, .favicon, .square]
}

/// Das vollständige Dokumentmodell — reine Daten, ohne AppKit.
///
/// Wird von `SceauDocument` (`NSDocument`) als JSON gelesen und geschrieben und
/// von `NSUndoManager` über Schnappschüsse versioniert.
///
/// ## Koordinatensystem (verbindlich für das gesamte Projekt)
/// Der Ursprung liegt **links oben**, die **Y-Achse wächst nach unten**.
///
/// Das entspricht SVG und den üblichen Gestaltungswerkzeugen, wodurch der
/// SVG-Export ohne jede Spiegelung auskommt — bei einer App, deren Kernzweck
/// der saubere Export ist, wiegt das schwerer als die Nähe zur AppKit-Vorgabe.
/// Der Preis ist genau eine Stelle, die es umdrehen muss: die Canvas-`NSView`
/// meldet dafür `isFlipped == true`, und der PDF-Export spiegelt einmalig.
/// Jede Geometrie in `SceauCore` rechnet ausnahmslos in dieser Konvention.
public struct Document: Equatable, Sendable, Codable {
    /// Version des Dateiformats. Wird beim Laden geprüft, damit spätere
    /// Formatänderungen erkennbar bleiben statt still falsch interpretiert zu werden.
    public var formatVersion: Int
    public var artboard: Artboard
    /// Die Elemente in Z-Reihenfolge: **Index 0 liegt zuunterst** und wird
    /// zuerst gezeichnet. Die Ebenenliste in der Oberfläche zeigt sie daher
    /// umgekehrt an, weil dort das oberste Element oben stehen soll.
    public var nodes: [Node]

    /// Aktuelle Formatversion, die diese Programmfassung schreibt.
    public static let currentFormatVersion = 1

    public init(
        formatVersion: Int = Document.currentFormatVersion,
        artboard: Artboard,
        nodes: [Node] = []
    ) {
        self.formatVersion = formatVersion
        self.artboard = artboard
        self.nodes = nodes
    }

    /// Ein leeres Dokument in der Vorgabegrösse für App-Icons.
    public static func empty(preset: ArtboardPreset = .appIcon) -> Document {
        Document(artboard: Artboard(size: preset.size))
    }
}
