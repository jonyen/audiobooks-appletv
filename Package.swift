// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudiobooksCore",
    platforms: [.macOS(.v13), .tvOS(.v17)],
    targets: [
        .target(name: "AudiobooksCore", path: "AudiobooksTV/Core"),
        .testTarget(
            name: "AudiobooksCoreTests",
            dependencies: ["AudiobooksCore"],
            path: "Tests/AudiobooksCoreTests"
        ),
    ]
)
