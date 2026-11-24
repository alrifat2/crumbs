import SwiftUI

@main
struct CrumbsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            LabeledContent("Launcher shortcut", value: "⌃⇧Space")
                .padding(24)
                .frame(width: 320)
        }
    }
}
