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
}
