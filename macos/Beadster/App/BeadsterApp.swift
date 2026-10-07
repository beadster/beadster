// beadster 2.0: the window on BeadsKit; each place's view lands in its own step.
import SwiftUI

@main
struct BeadsterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Beadster", id: "main") {
            root
        }
        .defaultSize(width: 1280, height: 760)
        .commands {
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

        Settings {
            SettingsBoard()
        }
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
