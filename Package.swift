// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SceauCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SceauCore", targets: ["SceauCore"])
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
        .testTarget(
            name: "SceauCoreTests",
            dependencies: ["SceauCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
