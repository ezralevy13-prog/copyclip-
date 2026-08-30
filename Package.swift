// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipwell",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Clipwell",
            path: "Sources/Clipwell",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
