// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Beadster",
    platforms: [.macOS(.v14)],
    products: [
        // CLI sync daemon
        .executable(
            name: "beadster-sync",
            targets: ["BeadsterCLI"]
        )
    ],
    targets: [
        // Shared code (used by both CLI and macOS app)
        .target(
            name: "BeadsterShared",
            dependencies: [],
            path: "Shared"
        ),

        // CLI sync daemon
        .executableTarget(
            name: "BeadsterCLI",
            dependencies: ["BeadsterShared"],
            path: "CLI",
            sources: ["main.swift", "CLISyncDaemon.swift"]
        )
    ]
)
