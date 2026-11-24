// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Crumbs",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Crumbs",
            path: "Crumbs/Crumbs",
            exclude: ["Assets.xcassets"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "Tests", dependencies: ["Crumbs"], path: "Tests")
    ]
)
