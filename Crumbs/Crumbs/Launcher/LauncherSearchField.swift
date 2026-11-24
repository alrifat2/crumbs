import AppKit
import SwiftUI

struct LauncherSearchField: NSViewRepresentable {
    @Environment(\.colorScheme) private var scheme
    @Binding var query: String
    let move: (Int) -> Void
    let submit: () -> Void
    let cancel: () -> Void

    final class Field: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.initialFirstResponder = self
            window?.makeFirstResponder(self)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LauncherSearchField

        init(_ parent: LauncherSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.query = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch command {
            case #selector(NSResponder.moveUp(_:)): parent.move(-1)
            case #selector(NSResponder.moveDown(_:)): parent.move(1)
            case #selector(NSResponder.insertNewline(_:)): parent.submit()
            case #selector(NSResponder.cancelOperation(_:)): parent.cancel()
            default: return false
            }
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.setAccessibilityLabel("Search apps and commands")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.font = .systemFont(ofSize: Theme.searchFontSize)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        let ink: NSColor = scheme == .dark ? .white : .black
        field.textColor = ink.withAlphaComponent(Theme.primaryAlpha)
        field.placeholderAttributedString = NSAttributedString(
            string: "Search apps and commands...",
            attributes: [
                .font: NSFont.systemFont(ofSize: Theme.searchFontSize),
                .foregroundColor: ink.withAlphaComponent(Theme.secondaryAlpha)
            ]
        )
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertionPointColor = ink
        }
        context.coordinator.parent = self
        if field.stringValue != query { field.stringValue = query }
    }
}
