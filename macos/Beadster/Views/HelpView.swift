//
//  HelpView.swift
//  Beadster
//
//  Help and support view
//

import SwiftUI
import AppKit

struct HelpView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Help & Support")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.bdSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(spacing: BDSpacing.lg) {
                    // Contact section
                    BDSettingsSection("CONTACT") {
                        Button {
                            if let url = URL(string: "mailto:hi@beadster.ai") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            BDSettingsRow(
                                icon: "envelope.fill",
                                iconColor: BDColors.iconBlue,
                                title: "email",
                                subtitle: "hi@beadster.ai",
                                showExternalArrow: true
                            )
                            .padding(.horizontal, BDSpacing.lg)
                            .padding(.vertical, BDSpacing.sm)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button {
                            if let url = URL(string: "imessage://+14159108321") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            BDSettingsRow(
                                icon: "message.fill",
                                iconColor: BDColors.iconGreen,
                                title: "imessage",
                                subtitle: "+1 415-910-8321",
                                showExternalArrow: true
                            )
                            .padding(.horizontal, BDSpacing.lg)
                            .padding(.vertical, BDSpacing.sm)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button {
                            if let url = URL(string: "https://github.com/beadster/beadster") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            BDSettingsRow(
                                icon: "curlybraces",
                                iconColor: BDColors.iconIndigo,
                                title: "source code",
                                subtitle: "github.com/beadster/beadster",
                                showExternalArrow: true
                            )
                            .padding(.horizontal, BDSpacing.lg)
                            .padding(.vertical, BDSpacing.sm)
                        }
                        .buttonStyle(.plain)
                    }

                    // Support section
                    BDSettingsSection("SUPPORT") {
                        Button {
                            if let url = URL(string: "https://patronat.com/anton+") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            BDSettingsRow(
                                icon: "heart.fill",
                                iconColor: BDColors.iconRed,
                                title: "support development",
                                subtitle: "one time or recurring donations",
                                showExternalArrow: true
                            )
                            .padding(.horizontal, BDSpacing.lg)
                            .padding(.vertical, BDSpacing.sm)
                        }
                        .buttonStyle(.plain)
                    }

                    // Other Products section
                    BDSettingsSection("OTHER PRODUCTS") {
                        Button {
                            if let url = URL(string: "https://tinydot.com") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            BDSettingsRow(
                                icon: "globe",
                                iconColor: BDColors.iconPurple,
                                title: "tinydot",
                                subtitle: "website builder",
                                showExternalArrow: true
                            )
                            .padding(.horizontal, BDSpacing.lg)
                            .padding(.vertical, BDSpacing.sm)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button {
                            if let url = URL(string: "https://original.me") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            BDSettingsRow(
                                icon: "globe",
                                iconColor: BDColors.iconOrange,
                                title: "original",
                                subtitle: "tool for podcast power listeners",
                                showExternalArrow: true
                            )
                            .padding(.horizontal, BDSpacing.lg)
                            .padding(.vertical, BDSpacing.sm)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button {
                            if let url = URL(string: "https://sublimated.com") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            BDSettingsRow(
                                icon: "globe",
                                iconColor: BDColors.iconCyan,
                                title: "sublimated",
                                subtitle: "native SQL IDE",
                                showExternalArrow: true
                            )
                            .padding(.horizontal, BDSpacing.lg)
                            .padding(.vertical, BDSpacing.sm)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button {
                            if let url = URL(string: "https://capncap.com") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            BDSettingsRow(
                                icon: "globe",
                                iconColor: BDColors.iconPink,
                                title: "capncap",
                                subtitle: "multi-stream screen recorder",
                                showExternalArrow: true
                            )
                            .padding(.horizontal, BDSpacing.lg)
                            .padding(.vertical, BDSpacing.sm)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button {
                            if let url = URL(string: "https://patronat.com") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            BDSettingsRow(
                                icon: "globe",
                                iconColor: BDColors.iconRed,
                                title: "patronat",
                                subtitle: "support creators you love",
                                showExternalArrow: true
                            )
                            .padding(.horizontal, BDSpacing.lg)
                            .padding(.vertical, BDSpacing.sm)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button {
                            if let url = URL(string: "https://tinysend.com") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            BDSettingsRow(
                                icon: "globe",
                                iconColor: BDColors.iconGreen,
                                title: "tinysend",
                                subtitle: "simple file sharing",
                                showExternalArrow: true
                            )
                            .padding(.horizontal, BDSpacing.lg)
                            .padding(.vertical, BDSpacing.sm)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button {
                            if let url = URL(string: "https://ultrathink.com") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            BDSettingsRow(
                                icon: "globe",
                                iconColor: BDColors.iconBlue,
                                title: "ultrathink",
                                subtitle: "AI search engine",
                                showExternalArrow: true
                            )
                            .padding(.horizontal, BDSpacing.lg)
                            .padding(.vertical, BDSpacing.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, BDSpacing.md)
            }
            .background(BDColors.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
