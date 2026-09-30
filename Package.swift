// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MicroCAM",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MicroCAMCore"),
        .executableTarget(name: "MicroCAMApp", dependencies: ["MicroCAMCore"]),
        .testTarget(name: "MicroCAMCoreTests", dependencies: ["MicroCAMCore"]),
        // Reads Sources/ and Resources/ as files: every UI text must exist in every language.
        .testTarget(name: "LocalizationTests"),
    ]
)
