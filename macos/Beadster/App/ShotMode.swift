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
import BeadsKit
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

    /// The scenes the rig can draw, and the window size each is captured at (points). The
    /// boards they are read against are in docs/design/shots (scripts/render-design).
    static let sizes: [String: NSSize] = [
        "shell": NSSize(width: 1280, height: 760), "shell-empty": NSSize(width: 1100, height: 680),
        "found": NSSize(width: 520, height: 430), "found-none": NSSize(width: 520, height: 430),
        "ready": NSSize(width: 1280, height: 760), "needs-you": NSSize(width: 1100, height: 680),
        "agents": NSSize(width: 1280, height: 680), "workflows": NSSize(width: 1100, height: 680),
        "map": NSSize(width: 1100, height: 720), "activity": NSSize(width: 1100, height: 640),
        "live": NSSize(width: 1100, height: 640),
        "history": NSSize(width: 1280, height: 560), "memories": NSSize(width: 1280, height: 600),
        "settings": NSSize(width: 520, height: 560),
        "problems": NSSize(width: 1500, height: 760), "folder-lost": NSSize(width: 1100, height: 640),
        "no-beads": NSSize(width: 1100, height: 640),
        "about": NSSize(width: 400, height: 330), "apps": NSSize(width: 460, height: 560),
    ]

    /// The bd fixtures scripts/mac-screenshots.sh copies into the rig's container.
    static var fixtures: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appending(path: "Fixtures")
    }

    @MainActor @ViewBuilder
    static func view(for scene: String, model: AppModel) -> some View {
        switch scene {
        case "shell": MainWindow(model: model).task { await model.load(plainFolder: fixtures) }
        case "needs-you":
            MainWindow(model: model).task {
                model.selection = .needsYou
                model.showInspector = false
                await model.load(plainFolder: fixtures)
            }
        case "workflows":
            MainWindow(model: model).task {
                model.selection = .workflows
                model.showInspector = false
                await model.load(plainFolder: fixtures)
            }
        case "map":
            MainWindow(model: model).task {
                model.selection = .workflows
                model.showInspector = false
                await model.load(plainFolder: fixtures)
                model.mapped = model.workflows.first { $0.workflow.root.title == "quick-check" }?.id
            }
        case "activity", "live":
            MainWindow(model: model).task {
                model.selection = .activity
                model.showInspector = false
                await model.load(plainFolder: fixtures)
            }
        case "history":
            MainWindow(model: model).task {
                model.sceneBusy = true
                defer { model.sceneBusy = false }
                await model.load(plainFolder: fixtures)
                // a real change made through beads, so the history has something to show
                if let row = model.readyRows.first(where: { $0.project == "one" }) {
                    await model.inspect(row.id)
                    await model.write { ws, id, actor throws(BeadsError) in
                        var e = BeadEdit(); e.title = "The only bead, renamed"; e.priority = 3
                        try await ws.update(id, e, as: actor)
                    }
                    if let bead = model.readyRows.first(where: { $0.project == "one" })?.bead {
                        await model.showHistory(of: bead, in: row.projectID)
                    }
                }
            }
        case "memories":
            MainWindow(model: model).task {
                model.sceneBusy = true
                defer { model.sceneBusy = false }
                model.selection = .memories
                await model.load(plainFolder: fixtures)
                model.selectedMemory = model.memories.first?.id
            }
        case "settings":
            ZStack { Color.clear; SettingsView(model: model) }.task {
                model.sceneBusy = true
                defer { model.sceneBusy = false }
                model.folders.addRigFolders(fixtures)
                await model.load(plainFolder: fixtures, key: "rig.fixtures")
            }
        case "agents":
            MainWindow(model: model).task {
                model.sceneBusy = true
                defer { model.sceneBusy = false }
                model.selection = .agents
                await model.load(plainFolder: fixtures)
                await model.inspectWork(model.working.first?.id)
            }
        case "ready":
            MainWindow(model: model).task {
                model.sceneBusy = true
                defer { model.sceneBusy = false }
                await model.load(plainFolder: fixtures)
                // a bead with labels, a comment, an epic and work it holds up
                let row = model.readyRows.first { $0.bead.title == "Conflicts lose a paragraph" }
                await model.inspect(row?.id)
            }
        case "problems":
            // every way a project can fail to open, as the detail pane draws it
            let problems: [Problem] = [
                .of(.needsMigration(dbVersion: 60, appVersion: 65)), .of(.needsNewerApp(dbVersion: 70, appVersion: 65)),
                .of(.legacy), .of(.server), .of(.failed(.busy("database is locked by another process (pid 41)"))),
                .of(.failed(.beads("dolt: manifest unreadable: unexpected EOF"))), .folderLost, .noBeadsYet,
            ].compactMap { $0 }
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                ForEach(0..<2, id: \.self) { r in
                    GridRow {
                        ForEach(0..<4, id: \.self) { c in
                            ProblemView(problem: problems[r * 4 + c]) { _ in }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.background)
                        }
                    }
                }
            }
            .background(.separator)
        case "folder-lost":
            MainWindow(model: model).task {
                model.sceneBusy = true
                defer { model.sceneBusy = false }
                model.showInspector = false
                model.folders.addRigFolders(fixtures)
                model.checkFolders()
                await model.load(plainFolder: fixtures, key: "rig.fixtures")
                model.selection = .folder("rig.gone")
            }
        case "no-beads":
            MainWindow(model: model).task {
                model.sceneBusy = true
                defer { model.sceneBusy = false }
                model.showInspector = false
                await model.load(plainFolder: fixtures)
                model.selection = model.entries.first { $0.found.name == "empty" }.map { .project($0.id) }
            }
        case "about": AboutWindow()
        case "apps": MoreAppsWindow()
        case "shell-empty": MainWindow(model: model)
        case "found", "found-none":
            // .task on a view whose body starts empty never runs: hang it on a container
            ZStack { Color.clear; FoundSheet(model: model) }.task {
                // the bd fixtures plus one old-format project, as a chosen folder would show them
                let root = scene == "found" ? fixtures : fixtures.appending(path: "empty/.beads")
                var found = ProjectScanner.scan(root, maxDepth: 1)
                if scene == "found" { found.append(FoundProject(name: "old-blog", relativePath: "old-blog/.beads", kind: .legacy)) }
                await model.present(GrantedFolder(key: "rig", path: "/Users/you/Developer"), access: PlainFolder(root), found: found)
            }
        default: MainWindow(model: model)
        }
    }

    /// Called once the app is up: hide, size, settle (the model done loading), report.
    @MainActor
    static func stage(_ scene: String, model: AppModel) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate() // never the active app: anton's typing stays where it is
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        try? FileManager.default.removeItem(at: reportURL)
        Task { @MainActor in
            for _ in 0..<50 {
                if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.contentView != nil }) {
                    let size = sizes[scene] ?? NSSize(width: 1280, height: 760)
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    // the window server pulls a window at -6000,-6000 back until a corner is on
                    // the display (found 2026-10-07): keep it BELOW the desktop so even that
                    // corner sits behind the wallpaper, and let clicks pass through
                    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
                    window.ignoresMouseEvents = true
                    if scene.hasPrefix("found") || scene == "settings" {
                        // in the app this is a sheet: no title bar of its own
                        window.styleMask.insert(.fullSizeContentView)
                        window.titlebarAppearsTransparent = true
                        window.titleVisibility = .hidden
                        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                            window.standardWindowButton(b)?.isHidden = true
                        }
                    }
                    window.setFrame(NSRect(x: -6000, y: -6000, width: size.width, height: size.height), display: true)
                    window.orderFront(nil)
                    try? await Task.sleep(for: .seconds(1))
                    for _ in 0..<1200 where model.loading || model.backgroundLoading || model.sceneBusy {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                    // SwiftUI may have resized or moved the window while it settled: off screen again
                    window.setFrame(NSRect(x: -6000, y: -6000, width: size.width, height: size.height), display: true)
                    try? await Task.sleep(for: .milliseconds(200))
                    var report: [String: Any] = ["window": window.windowNumber, "pid": Int(getpid())]
                    if let s = model.lastLoadSeconds { report["load_seconds"] = s }
                    if let s = model.firstPaintSeconds { report["ready_seconds"] = s }
                    report["windows"] = NSApp.windows.map { "\($0.windowNumber) \(type(of: $0)) main=\($0.canBecomeMain) visible=\($0.isVisible) \(Int($0.frame.width))x\(Int($0.frame.height))" }
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
