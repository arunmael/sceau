// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SceauCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SceauCore", targets: ["SceauCore"]),
        .executable(name: "sceau-icon", targets: ["SceauTools"])
    ],
    dependencies: [
        .package(url: "https://github.com/iShape-Swift/iOverlay", .upToNextMajor(from: "1.9.0"))
    ],
    targets: [
        .target(
            name: "SceauCore",
            dependencies: [
                .product(name: "iOverlay", package: "iOverlay")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Erzeugt das App-Icon aus einem Sceau-Dokument mit der eigenen
        // Exportstrecke — damit ist das Symbol reproduzierbar und zugleich ein
        // laufender Praxistest von Formen, Boolean, Verlauf und Rasterexport.
        .executableTarget(
            name: "SceauTools",
            dependencies: ["SceauCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SceauCoreTests",
            dependencies: ["SceauCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
