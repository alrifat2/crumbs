import Foundation
import Testing
@testable import Crumbs

struct ApplicationCatalogTests {
    @Test func discoversNestedAppsOnceAndSortsByName() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appending(path: UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        for path in ["Utilities/Zebra.app", "Alpha.app/Contents/Helper.app", ".Hidden.app", "Notes.txt"] {
            try manager.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
        }
        let apps = await LauncherApplication.discover(in: [root, root.appending(path: "Utilities")])
        #expect(apps.map(\.name) == ["Alpha", "Zebra"])
    }
}
