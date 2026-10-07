// beadster 2.0. The window is the boards' shell on sample data until BeadsKit lands;
// U1 builds the real navigation.
import SwiftUI

@main
struct BeadsterApp: App {
    var body: some Scene {
        WindowGroup("Beadster", id: "main") {
            root
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Bead") {}
                    .keyboardShortcut("n", modifiers: .command)
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
            ShotMode.view(for: scene).onAppear { ShotMode.stage(scene) }
        } else {
            ReadyBoard()
        }
        #else
        ReadyBoard()
        #endif
    }
}
