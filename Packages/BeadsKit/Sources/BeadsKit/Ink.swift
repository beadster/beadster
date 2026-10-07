import Foundation

/// The colours beadster writes words and status symbols in besides the system's: warning
/// (orange), danger (red), success (green). Light mode takes a darker ink, because the system orange on white is about 2:1;
/// dark mode keeps the system colours. InkTests hold every pair to 4.5:1 on the surfaces the
/// app draws on.
public struct RGB: Hashable, Sendable {
    public let r, g, b: Double
    public init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public func contrast(with other: RGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

public enum Ink {
    public struct Pair: Sendable { public let light: RGB; public let dark: RGB }
    public static let warning = Pair(light: RGB(0xA0_4E_00), dark: RGB(0xFF_9F_0A))
    public static let danger = Pair(light: RGB(0xBF_26_1A), dark: RGB(0xFF_8A_80))
    public static let success = Pair(light: RGB(0x1A_6B_2D), dark: RGB(0x30_D1_58))

    /// The surfaces words sit on: window, table stripe, grouped form, sidebar, in each mode.
    public static let lightSurfaces = [RGB(0xFF_FF_FF), RGB(0xF4_F5_F5), RGB(0xEC_EC_EC), RGB(0xE3_E3_E3)]
    public static let darkSurfaces = [RGB(0x1E_1E_1E), RGB(0x2A_2A_2A), RGB(0x32_32_32), RGB(0x3A_3A_3A)]
}
