import Foundation

nonisolated struct LauncherApplication: Identifiable, Sendable {
    let url: URL
    let name: String
    var id: URL { url }

    @concurrent
    static func discover() async -> [Self] {
        let manager = FileManager.default
        let roots = [
            URL(filePath: "/Applications"),
            URL(filePath: "/System/Applications"),
            // Safari can be installed here with a hidden symlink in /Applications.
            URL(filePath: "/System/Cryptexes/App/System/Applications")
        ] + manager.urls(for: .applicationDirectory, in: .userDomainMask)
        return await discover(in: roots)
    }

    @concurrent
    static func discover(in roots: [URL]) async -> [Self] {
        let manager = FileManager.default
        var apps: [Self] = []
        var seen: Set<URL> = []
        for root in roots {
            guard let items = manager.enumerator(at: root, includingPropertiesForKeys: [.localizedNameKey],
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            while let url = items.nextObject() as? URL {
                if Task.isCancelled { return [] }
                guard url.pathExtension.lowercased() == "app" else { continue }
                items.skipDescendants()
                guard seen.insert(url.resolvingSymlinksInPath()).inserted else { continue }
                let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                    ?? url.lastPathComponent
                apps.append(Self(url: url, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
