import AppKit

/// The app's entry point, and the single symbol the executable target needs.
public enum ClipwellApp {
    public static func run() {
        // Menu-bar app: `.accessory` keeps it out of the Dock and the app
        // switcher. The Info.plist sets LSUIElement too, so a bare `swift run`
        // behaves the same as the bundled app.
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // The delegate is owned by nothing else, so hold it for the process
        // lifetime rather than letting it deallocate out from under AppKit.
        retainedDelegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    private static var retainedDelegate: AppDelegate?
}
