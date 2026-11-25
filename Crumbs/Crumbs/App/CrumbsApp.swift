import SwiftUI

@main
struct CrumbsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            LauncherSettingsView()
        }
    }
}
