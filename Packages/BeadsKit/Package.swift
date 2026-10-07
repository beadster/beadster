// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BeadsKit",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [.library(name: "BeadsKit", targets: ["BeadsKit"])],
    targets: [
        .target(name: "BeadsKit"),
        .testTarget(name: "BeadsKitTests", dependencies: ["BeadsKit"], resources: [.copy("Fixtures")]),
    ]
)
