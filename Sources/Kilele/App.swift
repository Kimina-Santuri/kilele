import AppKit

// Kilele lives in the notch: no Dock icon, no main window.
@main
enum KileleApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // NSApplication holds its delegate weakly; without this an optimised build may free it (and the notch) at once.
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController()
    }
}
