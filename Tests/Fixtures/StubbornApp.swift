import AppKit

@MainActor
final class StubbornDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 170), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Killer Test App"
        let label = NSTextField(wrappingLabelWithString: "Disposable verification app\n\nI intentionally refuse normal Quit.\nUse Killer to force quit only this app.")
        label.frame = NSRect(x: 24, y: 24, width: 372, height: 120)
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Killer Test App", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        NSApp.mainMenu = menu
        NSApp.activate()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }
}
@main
struct FixtureMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = StubbornDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
