import CoreGraphics
import Foundation
import SceauCore

// Erzeugt das App-Icon aus einem Sceau-Dokument — mit Sceau' eigener
// Exportstrecke. Das Dokument wird mitgeschrieben, damit sich das Icon in der
// App selbst öffnen und ändern lässt, statt in einem fremden Programm.
//
// Aufruf:  swift run sceau-icon <Projektwurzel>

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

/// Ein Siegel: abgerundetes Quadrat mit Verlauf, darauf ein weisser Ring.
func makeIconDocument() throws -> Document {
    var document = Document(artboard: Artboard(size: CGSize(width: 1024, height: 1024)))

    // Der Rand bleibt frei: macOS setzt Programmsymbole auf ein Raster, bei dem
    // die Fläche nicht bis an die Kante läuft.
    var backgroundStyle = Style()
    backgroundStyle.fill = .linearGradient(Gradient(
        stops: [
            GradientStop(color: RGBAColor(red: 0.31, green: 0.27, blue: 0.90), location: 0),
            GradientStop(color: RGBAColor(red: 0.49, green: 0.23, blue: 0.93), location: 1)
        ],
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 1, y: 1)
    ))
    let background = Node(
        name: "Grund",
        style: backgroundStyle,
        content: .shape(.rectangle(
            frame: CGRect(x: 86, y: 86, width: 852, height: 852),
            cornerRadius: 190
        ))
    )

    // Der Ring entsteht als echte boolesche Subtraktion, nicht als Kontur:
    // So ist er im Dokument eine einzige Fläche und bleibt beim Skalieren exakt.
    let outer = ShapeGeometry.path(for: .ellipse(
        frame: CGRect(x: 292, y: 292, width: 440, height: 440)
    ))
    let inner = ShapeGeometry.path(for: .ellipse(
        frame: CGRect(x: 372, y: 372, width: 280, height: 280)
    ))
    let ringPath = try BooleanOperator.apply(.subtract, subject: outer, clip: inner)

    var ringStyle = Style()
    ringStyle.fill = .solid(.white)
    let ring = Node(name: "Siegel", style: ringStyle, content: .path(ringPath))

    document.nodes = [background, ring]
    return document
}

/// Die Grössen, die ein macOS-Programmsymbol braucht, samt Dateinamen.
let variants: [(size: Int, file: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

let document = try makeIconDocument()

// Quelldokument mitschreiben, damit das Icon in Sceau bearbeitbar bleibt.
let designDirectory = root.appendingPathComponent("Design", isDirectory: true)
try FileManager.default.createDirectory(at: designDirectory, withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(document).write(
    to: designDirectory.appendingPathComponent("AppIcon.sceau"),
    options: .atomic
)

let iconSet = root.appendingPathComponent(
    "App/Sceau/Resources/Assets.xcassets/AppIcon.appiconset",
    isDirectory: true
)
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

// Jede Kantenlänge nur einmal rastern, auch wenn sie zweimal gebraucht wird.
var rendered: [Int: Data] = [:]
for size in Set(variants.map(\.size)).sorted() {
    rendered[size] = try RasterExporter.pngData(document, pixelWidth: size, pixelHeight: size)
}

var entries: [String] = []
for variant in variants {
    guard let data = rendered[variant.size] else { continue }
    try data.write(to: iconSet.appendingPathComponent(variant.file), options: .atomic)

    let base = variant.file.contains("@2x") ? variant.size / 2 : variant.size
    let scale = variant.file.contains("@2x") ? "2x" : "1x"
    entries.append("""
        {
          "filename" : "\(variant.file)",
          "idiom" : "mac",
          "scale" : "\(scale)",
          "size" : "\(base)x\(base)"
        }
    """)
}

let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(
    to: iconSet.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

print("App-Icon erzeugt: \(variants.count) Dateien, Quelldokument unter Design/AppIcon.sceau")
