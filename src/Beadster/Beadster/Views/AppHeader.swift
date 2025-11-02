//
//  AppHeader.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/19/25.
//

import SwiftUI

struct AppHeader: View {
    @Binding var contentMode: ContentMode
    @Binding var isPinned: Bool

    var body: some View {
        HStack(spacing: 4) {
            Spacer()

            // New Issue button
            Button(action: {
                print("➕ New issue clicked!")
                contentMode = .newIssue
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .background(AppConfig.showDebugColors ? Color.green.opacity(0.5) : Color.clear)
            .border(AppConfig.showDebugColors ? Color.green : Color.clear, width: 2)

            // Settings button
            Button(action: {
                print("⚙️  Gear icon clicked! Current mode: \(contentMode)")
                contentMode = .settings
                print("⚙️  Changed to settings mode")
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .background(AppConfig.showDebugColors ? Color.purple.opacity(0.5) : Color.clear)
            .border(AppConfig.showDebugColors ? Color.purple : Color.clear, width: 2)

            // Help button
            Button(action: {
                print("❓ Help icon clicked!")
                contentMode = .help
            }) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .background(AppConfig.showDebugColors ? Color.blue.opacity(0.5) : Color.clear)
            .border(AppConfig.showDebugColors ? Color.blue : Color.clear, width: 2)

            // Pin button
            Button(action: {
                isPinned.toggle()
                print("📌 Pin clicked!")
            }) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .background(AppConfig.showDebugColors ? Color.orange.opacity(0.5) : Color.clear)
            .border(AppConfig.showDebugColors ? Color.orange : Color.clear, width: 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 0)
        .frame(height: LayoutConstants.appHeaderHeight)
        .background(AppConfig.showDebugColors ? Color.red.opacity(0.3) : Color.clear)
        .border(AppConfig.showDebugColors ? Color.red : Color.clear, width: 2)
        .overlay(
            AppConfig.showDebugColors ? AnyView(
                Text("H:\(LayoutConstants.appHeaderHeight)")
                    .font(.system(size: 8))
                    .foregroundColor(.primary)
                    .position(x: 200, y: 14)
            ) : AnyView(EmptyView())
        )
        .allowsHitTesting(true)
        .zIndex(100)
    }
}
