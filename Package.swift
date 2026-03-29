// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "voice-input",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "VoiceInput",
            targets: ["VoiceInput"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "VoiceInput",
            path: "Sources/VoiceInput",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "VoiceInputTests",
            dependencies: ["VoiceInput"],
            path: "Tests/VoiceInputTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
