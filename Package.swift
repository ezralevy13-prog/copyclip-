// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipwell",
    platforms: [.macOS(.v13)],
    targets: [
        // All logic lives in a library so it can be exercised by tests. The
        // executable is a three-line shim; without this split the pure
        // functions -- classification, detection, eviction -- aren't reachable
        // from a test target at all.
        .target(
            name: "ClipwellCore",
            path: "Sources/ClipwellCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Clipwell",
            dependencies: ["ClipwellCore"],
            path: "Sources/Clipwell"
        ),
        .testTarget(
            name: "ClipwellCoreTests",
            dependencies: ["ClipwellCore"],
            path: "Tests/ClipwellCoreTests"
        )
    ]
)
