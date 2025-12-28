//
//  HelpView.swift
//  Beadster
//
//  Help and support view
//

import SwiftUI

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
            VStack(alignment: .leading, spacing: 20) {
                Text("Please reach out with any questions or feedback:")
                    .foregroundColor(.bdSecondary)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Email:")
                            .foregroundColor(.bdSecondary)
                        Link("anton@systemoperator.com", destination: URL(string: "mailto:anton@systemoperator.com")!)
                            .foregroundColor(.blue)
                    }

                    HStack {
                        Text("iMessage:")
                            .foregroundColor(.bdSecondary)
                        Link("+1 415-910-8321", destination: URL(string: "imessage://+14159108321")!)
                            .foregroundColor(.blue)
                    }
                    HStack {
                        Text("Support development:")
                            .foregroundColor(.bdSecondary)
                        Link("one time or recurring donations", destination: URL(string: "https://buymeacoffee.com/podviaznikov")!)
                            .foregroundColor(.blue)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Other Products")
                        .font(.headline)
                    HStack {
                        Link("tinydot.com", destination: URL(string: "https://tinydot.com")!)
                            .foregroundColor(.blue)
                        Text("- personal website builder")
                            .foregroundColor(.bdSecondary)
                    }
                    HStack {
                        Link("beadster.ai", destination: URL(string: "https://beadster.ai")!)
                            .foregroundColor(.blue)
                        Text("- local-first issue tracker")
                            .foregroundColor(.bdSecondary)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
