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
    dependencies: [
        .package(url: "https://github.com/SwiftGit2/SwiftGit2.git", from: "0.9.0")
    ],
    targets: [
        // Shared code (used by both CLI and macOS app)
        .target(
            name: "Shared",
            dependencies: [
                .product(name: "SwiftGit2", package: "SwiftGit2")
            ],
            path: "Shared"
        ),

        // CLI sync daemon
        .executableTarget(
            name: "BeadsterCLI",
            dependencies: ["Shared"],
            path: "CLI",
            sources: ["main.swift", "CLISyncDaemon.swift"]
        )
    ]
)
