// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Skjaldr",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Skjaldr", targets: ["SkjaldrApp"])
    ],
    targets: [
        .executableTarget(
            name: "SkjaldrApp",
            path: "Sources/SkjaldrApp"
        ),
        .testTarget(
            name: "SkjaldrTests",
            dependencies: ["SkjaldrApp"],
            path: "Tests/SkjaldrTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
