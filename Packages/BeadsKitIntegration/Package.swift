// swift-tools-version: 6.2
// BeadsKit against the REAL beads engine and bd-made fixtures. Needs the local build products:
//   bash macos/BeadsFFI/build.sh test && bash macos/BeadsFFI/build.sh archive && bash macos/BeadsFFI/fixtures.sh
// Q3's numbers: swift test -c release --filter Performance
// Kept apart from BeadsKit so BeadsKit's own tests never need the 248 MB archive.
import PackageDescription

let package = Package(
    name: "BeadsKitIntegration",
    platforms: [.macOS("27.0")],
    dependencies: [.package(path: "../BeadsKit"), .package(path: "../../../common/swift-packages/FSEventsWatcher")],
    targets: [
        .binaryTarget(name: "BeadsFFI", path: "../../macos/BeadsFFI/build/BeadsFFI.xcframework"),
        .target(name: "BeadsFFIEngine", dependencies: ["BeadsKit", "BeadsFFI"],
                linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("Security"), .linkedLibrary("resolv")]),
        .testTarget(name: "IntegrationTests", dependencies: ["BeadsFFIEngine", "BeadsKit", "FSEventsWatcher"]),
    ]
)
