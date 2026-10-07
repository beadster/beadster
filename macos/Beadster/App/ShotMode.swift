// The screenshot rig: the app draws one scene, hidden, for scripts/mac-screenshots.sh. DEBUG only.
//
// WHAT IT MUST NEVER DO
// - touch anton's beadster: the scene is refused unless the bundle id ends in ".rig", so the
//   rig has its own sandbox container, preferences and bookmarks
// - show itself: no Dock icon, never activates, the window sits at -6000,-6000. The script grabs
//   it with `screencapture -l` (cacheDisplay draws the macOS 27 glass sidebar blank), so the app
//   only reports its window number into its container
#if DEBUG
import AppKit
import SwiftUI

enum ShotMode {
    /// BEADSTER_SHOT names the scene; absent means a normal launch.
    static var scene: String? {
        guard Bundle.main.bundleIdentifier?.hasSuffix(".rig") == true else { return nil }
        return ProcessInfo.processInfo.environment["BEADSTER_SHOT"]
    }

    static var dark: Bool { ProcessInfo.processInfo.environment["BEADSTER_SHOT_APPEARANCE"] == "dark" }

    /// Where the window number goes: inside the container, because the app is sandboxed.
    static var reportURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "shot-window.json")
    }

    /// The scenes the rig can draw, and the window size each is captured at (points).
    static let sizes: [String: NSSize] = [
        "welcome": NSSize(width: 1100, height: 680), "needs-you": NSSize(width: 1100, height: 680),
        "ready": NSSize(width: 1280, height: 760), "agents": NSSize(width: 1280, height: 680),
        "workflows": NSSize(width: 1100, height: 680), "map": NSSize(width: 1100, height: 720),
        "activity": NSSize(width: 1100, height: 600), "history": NSSize(width: 1280, height: 560),
        "memories": NSSize(width: 1280, height: 600),
    ]

    @MainActor @ViewBuilder
    static func view(for scene: String) -> some View {
        switch scene {
        case "welcome": WelcomeBoard()
        case "needs-you": NeedsYouBoard()
        case "agents": AgentsBoard()
        case "workflows": WorkflowsBoard()
        case "map": GraphBoard()
        case "activity": ActivityBoard()
        case "history": HistoryBoard()
        case "memories": MemoriesBoard()
        default: ReadyBoard()
        }
    }

    /// Called once the app is up: hide, size, settle, report.
    @MainActor
    static func stage(_ scene: String) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        try? FileManager.default.removeItem(at: reportURL)
        Task { @MainActor in
            for _ in 0..<50 {
                if let window = NSApp.windows.first(where: { $0.isVisible || $0.contentView != nil }) {
                    let size = sizes[scene] ?? NSSize(width: 1280, height: 760)
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.setFrame(NSRect(x: -6000, y: -6000, width: size.width, height: size.height), display: true)
                    window.orderFront(nil)
                    try? await Task.sleep(for: .seconds(1))
                    let report = ["window": window.windowNumber, "pid": Int(getpid())]
                    if let data = try? JSONSerialization.data(withJSONObject: report) {
                        try? data.write(to: reportURL)
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
#endif
