// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CallRecorderKit",
    platforms: [.macOS(.v26), .iOS(.v17)],
    products: [
        .library(name: "AudioCapture", targets: ["AudioCapture"]),
        .library(name: "Transcription", targets: ["Transcription"]),
        .library(name: "CodexClient", targets: ["CodexClient"]),
        .library(name: "CallLibrary", targets: ["CallLibrary"]),
        .library(name: "Localization", targets: ["Localization"]),
        .executable(name: "spike", targets: ["spike"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
    ],
    targets: [
        /// The interface language, chosen from the system's at launch, and the texts in both languages.
        .target(name: "Localization"),
        .target(name: "AudioCapture", dependencies: ["Localization"]),
        .target(
            name: "Transcription",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                "AudioCapture",
                "Localization",
            ]
        ),
        .target(name: "CodexClient", dependencies: ["Localization"]),
        /// What both apps show and do with a recording: the view models, search, export, playback and voices.
        .target(name: "CallLibrary", dependencies: ["AudioCapture", "Transcription", "CodexClient", "Localization"]),
        .executableTarget(
            name: "spike",
            dependencies: ["AudioCapture", "Transcription", "CodexClient"]
        ),
        .testTarget(name: "LocalizationTests", dependencies: ["Localization"]),
        .testTarget(name: "AudioCaptureTests", dependencies: ["AudioCapture"]),
        .testTarget(name: "TranscriptionTests", dependencies: ["Transcription", "AudioCapture"]),
        .testTarget(name: "CodexClientTests", dependencies: ["CodexClient"]),
        .testTarget(
            name: "CallLibraryTests", dependencies: ["CallLibrary", "AudioCapture", "Transcription", "CodexClient", "Localization"]
        ),
    ]
)
