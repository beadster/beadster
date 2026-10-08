// beadster 2.0: the window on BeadsKit; each place's view lands in its own step.
import AppKit
import SwiftUI

@main
struct BeadsterApp: App {
    @State private var model = AppModel()
    /// Settings › Show in the Menu Bar: the person decides (HIG), off until they do.
    @AppStorage("menuBarExtra") private var showMenuBarExtra = false
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Beadster", id: "main") {
            root
        }
        .defaultSize(width: 1280, height: 760)
        .commands {
            // About opens the family's card (AppCatalog), not AppKit's standard panel
            CommandGroup(replacing: .appInfo) {
                Button("About Beadster") { openWindow(id: "about") }
            }
            // the stock Help item asks for a Help Book beadster does not ship
            CommandGroup(replacing: .help) {
                Button("Beadster Website") { if let url = BeadsterAbout.site { NSWorkspace.shared.open(url) } }
                Button("Send Feedback") { BeadsterAbout.mail("beadster feedback") }
                Divider()
                Button("More Apps") { openWindow(id: "apps") }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Bead") {}
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.entries.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Divider()
                ForEach(Array([Place.needsYou, .ready, .agents, .blocked, .activity].enumerated()), id: \.offset) { i, place in
                    Button(place.title) { model.selection = place }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
                Divider()
                Button(model.showInspector ? "Hide Inspector" : "Show Inspector") { model.showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }

        Window("About Beadster", id: "about") { AboutWindow() }
            .windowResizability(.contentSize)
            .restorationBehavior(.disabled)

        Window("More Apps", id: "apps") { MoreAppsWindow() }
            .defaultSize(width: 460, height: 560)
            .restorationBehavior(.disabled)

        Settings {
            SettingsView(model: model)
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            BeadsterMenu(model: model)
        } label: {
            BeadsterMenuLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }

    @MainActor @ViewBuilder
    private var root: some View {
        #if DEBUG
        if let scene = ShotMode.scene {
            // a container that always appears: a scene whose view starts empty never fires onAppear
            ZStack { Color.clear; ShotMode.view(for: scene, model: model) }
                .onAppear { ShotMode.stage(scene, model: model) }
        } else {
            MainWindow(model: model).frame(minWidth: 900, minHeight: 560).task { await model.load() }
        }
        #else
        MainWindow(model: model).frame(minWidth: 900, minHeight: 560).task { await model.load() }
        #endif
    }
}
