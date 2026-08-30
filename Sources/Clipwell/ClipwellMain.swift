import ClipwellCore

/// Entry point.
///
/// Deliberately `@main` in a normal file rather than top-level code in
/// `main.swift`: top-level code is not main-actor isolated in Swift 5 language
/// mode, so it cannot call into AppKit setup, which is isolated throughout
/// (`NSApplication.shared`, `.delegate` and `.run()` are all main-actor). A
/// `@main` type can declare its `main()` as `@MainActor`, which is the same
/// shape SwiftUI's own `App` protocol uses.
@main
struct ClipwellMain {
    @MainActor
    static func main() {
        ClipwellApp.run()
    }
}
