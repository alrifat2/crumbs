import AppKit
import SwiftUI

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class LauncherWindowController {
    private var panel: LauncherPanel?
    var hotKeyAvailable = true
    private var outsideClickMonitor: Any?
    private var previousApp: NSRunningApplication?

    private func dismiss(restoreFocus: Bool) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        panel?.orderOut(nil)
        panel?.contentView = nil
        if restoreFocus { previousApp?.activate() }
        previousApp = nil
    }

    func toggle() {
        if panel?.isVisible == true {
            dismiss(restoreFocus: true)
        } else {
            show()
        }
    }

    func show() {
        if let front = NSWorkspace.shared.frontmostApplication, front != .current {
            previousApp = front
        }
        let window = panel ?? LauncherPanel(
            contentRect: NSRect(origin: .zero, size: Theme.panelSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        if panel == nil {
            panel = window
            window.title = "Crumbs"
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.isFloatingPanel = true
            window.becomesKeyOnlyIfNeeded = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        }
        if !window.isVisible || window.contentView == nil {
            window.contentView = NSHostingView(rootView: LauncherView(hotKeyAvailable: hotKeyAvailable) { [weak self] restore in self?.dismiss(restoreFocus: restore) })
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                guard NSApp.modalWindow == nil else { return }
                self?.dismiss(restoreFocus: false)
            }
            window.center()
            if let bounds = window.screen?.visibleFrame {
                var origin = window.frame.origin
                origin.y = max(bounds.minY, origin.y - Theme.downwardOffset)
                window.setFrameOrigin(origin)
            }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
