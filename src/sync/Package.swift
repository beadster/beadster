// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BeadsterSync",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "BeadsterSync",
            dependencies: [],
            path: "Sources"
        )
    ]
)
