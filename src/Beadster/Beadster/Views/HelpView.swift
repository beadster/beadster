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
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 20) {
                Text("Please me with any questions or feedback:")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Email:")
                            .foregroundColor(.secondary)
                        Link("anton@systemoperator.com", destination: URL(string: "mailto:anton@systemoperator.com")!)
                            .foregroundColor(.blue)
                    }

                    HStack {
                        Text("iMessage:")
                            .foregroundColor(.secondary)
                        Link("+1 415-910-8321", destination: URL(string: "imessage://+14159108321")!)
                            .foregroundColor(.blue)
                    }
                    HStack {
                        Text("Support development:")
                            .foregroundColor(.secondary)
                        Link("one time or recurring donations", destination: URL(string: "https://patronat.com/anton+")!)
                            .foregroundColor(.blue)
                    }
                }

                
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Other Products")
                        .font(.headline)
                    HStack {
                        Link("tinysend.com", destination: URL(string: "https://tinysend.com")!)
                            .foregroundColor(.blue)
                        Text("- indie newsletter publishing")
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
