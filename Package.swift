// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "serbin-sessions",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SerbinSessions", targets: ["SerbinSessions"]),
        .executable(name: "notch-hook", targets: ["notch-hook"]),
    ],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(name: "notch-hook", dependencies: ["IslandCore"]),
        .executableTarget(name: "SerbinSessions", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
