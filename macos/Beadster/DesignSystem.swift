//
//  DesignSystem.swift
//  Beadster
//

import SwiftUI
import AppKit

// MARK: - Colors
extension Color {
    static let bdSecondary = Color.primary.opacity(0.75)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - BDColors (namespace)

struct BDColors {
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let background = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : NSColor.white
    }))
    static let surface = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
            : NSColor.white
    }))
    static let divider = Color(nsColor: .separatorColor)

    // Icon colors
    static let iconBlue = Color(hex: "197BFF")
    static let iconGreen = Color(hex: "4FC46B")
    static let iconIndigo = Color(hex: "7045D9")
    static let iconPurple = Color(hex: "A24BD3")
    static let iconPink = Color(hex: "FF4FA0")
    static let iconRed = Color(hex: "FF5A2F")
    static let iconOrange = Color(hex: "FF9E1F")
    static let iconCyan = Color(hex: "00B8F0")
}

// MARK: - Spacing

struct BDSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

// MARK: - Corner Radius

struct BDRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
}

// MARK: - Typography
extension Font {
    // Berkeley Mono - Logo
    static let bdLogoLarge = Font.custom("BerkeleyMono-Regular", size: 18)
    static let bdLogoMedium = Font.custom("BerkeleyMono-Regular", size: 13)

    // Berkeley Mono - IDs and technical elements
    static let bdIssueID = Font.custom("BerkeleyMono-Regular", size: 9)
    static let bdExternalRef = Font.custom("BerkeleyMono-Regular", size: 9)
    static let bdHashID = Font.custom("BerkeleyMono-Regular", size: 10)
    static let bdProjectBadge = Font.custom("BerkeleyMono-Regular", size: 10)
    static let bdMonoSmall = Font.custom("BerkeleyMono-Regular", size: 11)
}

// MARK: - Settings Row

struct BDSettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let showExternalArrow: Bool

    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        showExternalArrow: Bool = false
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.showExternalArrow = showExternalArrow
    }

    var body: some View {
        HStack(spacing: BDSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(BDColors.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.bdMonoSmall)
                        .foregroundColor(BDColors.textSecondary)
                }
            }

            Spacer()

            if showExternalArrow {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BDColors.textSecondary)
            }
        }
    }
}

// MARK: - Settings Card

struct BDSettingsCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(BDColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: BDRadius.lg))
        .padding(.horizontal, BDSpacing.sm)
    }
}

// MARK: - Settings Section

struct BDSettingsSection<Content: View>: View {
    let header: String?
    let content: () -> Content

    init(_ header: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header = header {
                Text(header)
                    .font(.bdMonoSmall)
                    .foregroundColor(BDColors.textSecondary)
                    .padding(.horizontal, BDSpacing.lg)
                    .padding(.bottom, BDSpacing.sm)
            }

            BDSettingsCard {
                content()
            }
        }
    }
}
