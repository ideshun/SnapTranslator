// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapTranslator",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SnapTranslatorCore",
            path: "Sources/SnapTranslatorCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SnapTranslator",
            dependencies: ["SnapTranslatorCore"],
            path: "Sources/SnapTranslator",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SnapTranslatorTests",
            dependencies: ["SnapTranslatorCore"],
            path: "Tests/SnapTranslatorTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
