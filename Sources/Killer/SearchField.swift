import AppKit
import SwiftUI

/// A native search field with reliable first-responder routing from the Find menu.
struct ProcessSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(string: text)
        field.placeholderString = "Search name or PID"
        field.setAccessibilityLabel("Search name, process ID, or executable path")
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        context.coordinator.observe(field)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    static func dismantleNSView(_ field: NSSearchField, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        private var observer: NSObjectProtocol?
        private weak var field: NSSearchField?

        init(text: Binding<String>) { self.text = text }

        func observe(_ field: NSSearchField) {
            self.field = field
            observer = NotificationCenter.default.addObserver(forName: .killerFocusSearch, object: nil, queue: .main) { [weak self] _ in
                // Menu tracking must finish before changing the first responder.
                Task { @MainActor [weak self] in
                    guard let field = self?.field, let window = field.window else { return }
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(field)
                    field.selectText(nil)
                }
            }
        }

        func stopObserving() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
