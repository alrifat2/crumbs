import Foundation

enum SettingsCatalog {
    @concurrent
    static func discover() async -> [LauncherResult] {
        let root = URL(filePath: "/System/Library/ExtensionKit/Extensions")
        let extensions = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var panes: [LauncherResult] = []
        for url in extensions where url.pathExtension == "appex" {
            if Task.isCancelled { return [] }
            guard let bundle = Bundle(url: url),
                  let attributes = bundle.infoDictionary?["EXAppExtensionAttributes"] as? [String: Any],
                  attributes["EXExtensionPointIdentifier"] as? String == "com.apple.Settings.extension.ui",
                  let identifier = bundle.bundleIdentifier,
                  let target = URL(string: "x-apple.systempreferences:" + identifier),
                  let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                  !name.isEmpty else { continue }
            panes.append(LauncherResult(url: target, name: name, kind: .settings))
        }
        return panes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
