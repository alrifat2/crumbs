import Foundation

enum LauncherSearch {
    static func matches(_ apps: [LauncherApplication], query: String) -> [LauncherApplication] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? apps : apps.filter { $0.name.localizedStandardContains(term) }
    }
}

nonisolated struct LauncherResult: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case application = "Application"
        case settings = "System Settings"
        case file = "File"
        case folder = "Folder"
    }

    let url: URL
    let name: String
    let kind: Kind
    var id: URL { url }

    var application: LauncherApplication? {
        guard kind == .application else { return nil }
        return LauncherApplication(url: url, name: name)
    }
}

enum LauncherScope: String, CaseIterable {
    case file = "@file"

    var title: String {
        switch self { case .file: "Files" }
    }

    var symbol: String {
        switch self { case .file: "folder" }
    }

    static func suggestions(for input: String) -> [Self]? {
        guard input.hasPrefix("@") else { return nil }
        let prefix = input.lowercased()
        return allCases.filter { $0.rawValue.hasPrefix(prefix) }
    }

    static func activation(for input: String) -> (scope: Self, query: String)? {
        guard input.hasPrefix("@") else { return nil }
        let token = input.prefix(while: { !$0.isWhitespace })
        guard let scope = Self(rawValue: token.lowercased()) else { return nil }
        return (scope, String(input.dropFirst(token.count).drop(while: \.isWhitespace)))
    }
}
