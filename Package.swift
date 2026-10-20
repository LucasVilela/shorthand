// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shorthand",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (matching, typing buffer, placeholders) so it can be unit tested.
        .target(name: "ShorthandCore"),
        // The menu-bar app: keystroke monitor, expansion, editor UI.
        .executableTarget(name: "Shorthand", dependencies: ["ShorthandCore"]),
        .testTarget(name: "ShorthandCoreTests", dependencies: ["ShorthandCore"]),
    ]
)
