import AppKit
import SwiftUI

@main
struct KillerApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Killer", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 860, minHeight: 560)
                .task {
                    while !Task.isCancelled {
                        await model.refresh()
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
        }
        .defaultSize(width: 1080, height: 700)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Find Process") { NotificationCenter.default.post(name: .killerFocusSearch, object: nil) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Refresh Processes") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Force Quit Selected Process…") {
                    if let selected = model.selectedProcess { model.requestTermination(selected) }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedProcess == nil || model.activeOperation != nil || model.selectedProcess?.protection != nil)
            }
            CommandGroup(replacing: .help) {
                Button("Killer Help") {
                    NSWorkspace.shared.open(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Help.html"))
                }
            }
        }
    }
}

extension Notification.Name {
    static let killerFocusSearch = Notification.Name("Killer.focusSearch")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
