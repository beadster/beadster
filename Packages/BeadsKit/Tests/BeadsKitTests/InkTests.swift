import Testing
@testable import BeadsKit

@Test func everyInkReads4point5To1OnEverySurfaceInBothModes() {
    for (name, pair) in [("warning", Ink.warning), ("danger", Ink.danger), ("success", Ink.success)] {
        for s in Ink.lightSurfaces { #expect(pair.light.contrast(with: s) >= 4.5, "\(name) light on \(s)") }
        for s in Ink.darkSurfaces { #expect(pair.dark.contrast(with: s) >= 4.5, "\(name) dark on \(s)") }
    }
}

@Test func theSystemOrangeIsWhyTheLightInkExists() {
    #expect(RGB(0xFF_95_00).contrast(with: RGB(0xFF_FF_FF)) < 3) // macOS systemOrange, light
    #expect(abs(RGB(0x00_00_00).contrast(with: RGB(0xFF_FF_FF)) - 21) < 0.01)
}
