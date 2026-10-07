// The app's own logic (what BeadsKit doesn't carry): hosted in Beadster, so running it launches
// the app; `xcodebuild test -only-testing:BeadsterTests` is anton's [L] step, build-for-testing
// compiles it in every gate.
import AppCatalog
import AppKit
import BeadsKit
import Testing
@testable import Beadster

@MainActor
@Test func inksFollowTheAppearance() throws {
    for (pair, name) in [(Ink.warning, "warningInk"), (Ink.danger, "dangerInk"), (Ink.success, "successInk")] {
        let color = NSColor.ink(pair, name: NSColor.Name(name))
        for (look, want) in [(NSAppearance.Name.aqua, pair.light), (.darkAqua, pair.dark)] {
            let appearance = try #require(NSAppearance(named: look))
            var got = NSColor.black
            appearance.performAsCurrentDrawingAppearance { got = color.usingColorSpace(.sRGB) ?? .black }
            #expect(abs(got.redComponent - want.r) < 0.01 && abs(got.greenComponent - want.g) < 0.01
                    && abs(got.blueComponent - want.b) < 0.01, "\(name) in \(look.rawValue)")
        }
    }
}

@MainActor
@Test func notificationsDefaultToWhatSettingsShows() {
    for key in ["notify.gates", "notify.quiet", "notify.assigned", "notify.closed"] {
        UserDefaults.standard.removeObject(forKey: key)
    }
    #expect(Notifier.allowed(.gate) && Notifier.allowed(.quiet) && Notifier.allowed(.assigned))
    #expect(!Notifier.allowed(.closed))
    UserDefaults.standard.set(false, forKey: "notify.gates")
    #expect(!Notifier.allowed(.gate))
    UserDefaults.standard.removeObject(forKey: "notify.gates")
}

@Test func aboutNamesTheAppInLowercaseWithItsBuild() {
    let model = BeadsterAbout.model
    #expect(model.appName == "beadster")
    #expect(model.version.contains("("))
    #expect(BeadsterAbout.site?.host() == "beadster.ai")
}

@Test func aLostFolderIsItsOwnPlace() {
    #expect(Place.folder("k").symbol == "folder.badge.questionmark")
    #expect(Place.folder("k") != Place.project("k"))
}
