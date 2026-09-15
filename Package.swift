// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YuE2Studio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "YuE2Studio", path: "Sources/YuE2Studio")
    ],
    swiftLanguageVersions: [.v5]
)
