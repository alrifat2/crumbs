import SwiftUI

struct LauncherSettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Launcher shortcut", value: "⌃⇧Space")
        }
        .padding(24)
        .frame(width: 360)
    }
}
