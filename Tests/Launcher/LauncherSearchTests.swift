import Foundation
import Testing
@testable import Crumbs

@MainActor
struct LauncherSearchTests {
    let apps = ["Messages", "Safari"].map {
        LauncherApplication(url: URL(filePath: "/Applications/\($0).app"), name: $0)
    }

    @Test func blankQueryPreservesCatalogOrder() {
        #expect(LauncherSearch.matches(apps, query: " \n").map(\.id) == apps.map(\.id))
    }

    @Test func filtersByPartialNameIgnoringCaseAndOuterWhitespace() {
        #expect(LauncherSearch.matches(apps, query: "  SAF ").map(\.name) == ["Safari"])
        #expect(LauncherSearch.matches(apps, query: "missing").isEmpty)
    }

    @Test func scopeSuggestionsFilterLeadingTokens() {
        #expect(LauncherScope.suggestions(for: "@") == LauncherScope.allCases)
        #expect(LauncherScope.suggestions(for: "@Fi") == [.file])
        #expect(LauncherScope.suggestions(for: "@missing") == [])
        #expect(LauncherScope.suggestions(for: "notes @fi") == nil)
        #expect(LauncherScope.activation(for: "@fi") == nil)
    }

    @Test func fileTokenConsumesOnlyACompleteLeadingCommand() {
        #expect(LauncherScope.activation(for: "@file")?.query == "")
        #expect(LauncherScope.activation(for: "@FILE  budget 2026")?.query == "budget 2026")
        #expect(LauncherScope.activation(for: "@filename") == nil)
        #expect(LauncherScope.activation(for: "notes @file") == nil)
    }
}
