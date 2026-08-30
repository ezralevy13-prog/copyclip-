import AppKit

// Menu-bar app: `.accessory` keeps it out of the Dock and the app switcher.
// The Info.plist also sets LSUIElement, but setting it here too means a
// `swift run` from the command line behaves the same as the bundled app.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
