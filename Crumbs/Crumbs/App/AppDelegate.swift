import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launcher = LauncherWindowController()

    private lazy var hotKey = LauncherHotKey { [weak self] in self?.launcher.toggle() }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        FileSearch.stopIndexing()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launcher.hotKeyAvailable = hotKey.register()
        launcher.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launcher.show()
        return false
    }
}
