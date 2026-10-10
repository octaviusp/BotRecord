// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Rec",
    platforms: [.macOS("26.0")],
    targets: [
        .systemLibrary(name: "CSvtAv1", path: "Sources/CSvtAv1"),
        .systemLibrary(name: "COpus", path: "Sources/COpus"),
        .executableTarget(
            name: "Rec",
            dependencies: ["CSvtAv1", "COpus"],
            path: "Sources/Rec",
            swiftSettings: [.unsafeFlags(["-Xcc", "-I/opt/homebrew/include"])],
            linkerSettings: [.unsafeFlags(["-L/opt/homebrew/lib", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ],
    swiftLanguageModes: [.v5]
)
