// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claude-island",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeIsland", targets: ["ClaudeIsland"]),
        .executable(name: "notch-hook", targets: ["notch-hook"]),
    ],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(name: "notch-hook", dependencies: ["IslandCore"]),
        .executableTarget(name: "ClaudeIsland", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
