// swift-tools-version: 6.2
import Foundation
import PackageDescription

let rust = "Crumbs/Crumbs/Launcher/FileSearch/Rust"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

let package = Package(
    name: "Crumbs",
    platforms: [.macOS(.v26)],
    targets: [
        .systemLibrary(name: "FileSearchCore", path: rust + "/include"),
        .executableTarget(
            name: "Crumbs",
            dependencies: ["FileSearchCore"],
            path: "Crumbs/Crumbs",
            exclude: ["Assets.xcassets", "Launcher/FileSearch/Rust"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.unsafeFlags(["-L", root.appendingPathComponent(".build/file-search").path]),
                             .linkedLibrary("crumbs_file_search"), .linkedFramework("CoreServices")]
        ),
        .testTarget(name: "Tests", dependencies: ["Crumbs"], path: "Tests")
    ]
)
