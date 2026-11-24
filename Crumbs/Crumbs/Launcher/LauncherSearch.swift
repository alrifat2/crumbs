import Foundation

enum LauncherSearch {
    static func matches(_ apps: [LauncherApplication], query: String) -> [LauncherApplication] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? apps : apps.filter { $0.name.localizedStandardContains(term) }
    }
}
