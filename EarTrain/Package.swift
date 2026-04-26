// swift-tools-version: 5.9
import PackageDescription

// Embed Info.plist into the binary so macOS honours NSMicrophoneUsageDescription
// for SPM executable targets (no .app bundle to carry it otherwise).
let infoPlistPath = "\(Context.packageDirectory)/Info.plist"

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
        // Executable — @main entry point only, imports EarTrainLib
        .executableTarget(
            name: "EarTrain",
            dependencies: ["EarTrainLib"],
            path: "Sources/EarTrain",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath,
                ])
            ]
        ),

        // Library — all app logic, testable
        .target(
            name: "EarTrainLib",
            dependencies: [
                .product(name: "AudioKit", package: "AudioKit"),
            ],
            path: "Sources/EarTrainLib",
            resources: [.copy("Samples"), .copy("Samples_normalized"), .process("audie.png"), .copy("Audie.icns")]
        ),

        // Tests
        .testTarget(
            name: "EarTrainTests",
            dependencies: ["EarTrainLib"],
            path: "Tests/EarTrainTests"
        ),
    ]
)
