// BeadsKit's Ink as SwiftUI colours that follow the appearance: the darker ink in light
// mode, the system-like colour in dark. Every orange or red word and symbol uses these.
import AppKit
import BeadsKit
import SwiftUI

extension Color {
    static let warningInk = Color(nsColor: .ink(Ink.warning, name: "warningInk"))
    static let dangerInk = Color(nsColor: .ink(Ink.danger, name: "dangerInk"))
    static let successInk = Color(nsColor: .ink(Ink.success, name: "successInk"))
}

extension NSColor {
    static func ink(_ pair: Ink.Pair, name: String) -> NSColor {
        NSColor(name: name) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = dark ? pair.dark : pair.light
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        }
    }
}
