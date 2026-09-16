// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tunesmith",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tunesmith", path: "Sources/Tunesmith")
    ],
    swiftLanguageVersions: [.v5]
)
