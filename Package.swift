// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MicroCAM",
    platforms: [.macOS(.v14)],
    // The one third-party dependency: Sparkle, the standard updater for Mac
    // apps outside the App Store (signature-checked downloads, install, relaunch).
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "MicroCAMCore"),
        .executableTarget(name: "MicroCAMApp", dependencies: [
            "MicroCAMCore",
            .product(name: "Sparkle", package: "Sparkle"),
        ]),
        .testTarget(name: "MicroCAMCoreTests", dependencies: ["MicroCAMCore"]),
        // Reads Sources/ and Resources/ as files: every UI text must exist in every language.
        .testTarget(name: "LocalizationTests"),
    ]
)
