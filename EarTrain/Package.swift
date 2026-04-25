// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EarTrain",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(
            url: "https://github.com/AudioKit/AudioKit",
            from: "5.6.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "EarTrain",
            dependencies: [
                .product(name: "AudioKit", package: "AudioKit"),
            ],
            path: "Sources/EarTrain",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
