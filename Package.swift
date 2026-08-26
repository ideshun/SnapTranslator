// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapTranslator",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SnapTranslator",
            path: "Sources/SnapTranslator",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
