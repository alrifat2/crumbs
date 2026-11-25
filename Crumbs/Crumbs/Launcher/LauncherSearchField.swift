import AppKit
import SwiftUI

struct LauncherSearchField: NSViewRepresentable {
    @Environment(\.colorScheme) private var scheme
    @Binding var query: String
    let fileScope: Bool
    let enterFolder: () -> Bool
    let leaveScope: () -> Void
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
            case #selector(NSResponder.insertTab(_:)): return parent.enterFolder()
            case #selector(NSResponder.deleteBackward(_:)) where parent.fileScope && textView.string.isEmpty:
                parent.leaveScope()
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
        field.setAccessibilityLabel(fileScope ? "Search files and folders" : "Search apps and commands")
        field.textColor = ink.withAlphaComponent(Theme.primaryAlpha)
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertionPointColor = ink
        }
        context.coordinator.parent = self
        if field.stringValue != query { field.stringValue = query }
    }
}
