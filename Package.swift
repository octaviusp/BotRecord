// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Rec",
    platforms: [.macOS("26.0")],
    dependencies: [
        // On-device live transcription (Nemotron 3.5 Streaming on MLX). Only `NemotronStreamingASR` is linked.
        .package(url: "https://github.com/soniqo/speech-swift", exact: "0.0.28"),
        // Pinned because scripts/build.sh bundles the prebuilt metallib of its vendored MLX core (0.31.1):
        // bumping it means bumping the metallib too (the script fails the build when they disagree).
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.6"),
    ],
    targets: [
        .systemLibrary(name: "CSvtAv1", path: "Sources/CSvtAv1"),
        .systemLibrary(name: "COpus", path: "Sources/COpus"),
        .executableTarget(
            name: "Rec",
            dependencies: [
                "CSvtAv1", "COpus",
                .product(name: "NemotronStreamingASR", package: "speech-swift"),
                // Only for `Memory.clearCache()`: frees the GPU buffers when the idle model is unloaded.
                .product(name: "MLX", package: "mlx-swift"),
            ],
            path: "Sources/Rec",
            swiftSettings: [.unsafeFlags(["-Xcc", "-I/opt/homebrew/include"])],
            linkerSettings: [.unsafeFlags(["-L/opt/homebrew/lib", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ],
    swiftLanguageModes: [.v5]
)
