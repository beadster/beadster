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
        HStack(spacing: 8) {
            Spacer()

            Button(action: {
                print("⚙️  Gear icon clicked! Current mode: \(contentMode)")
                contentMode = .settings
                print("⚙️  Changed to settings mode")
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.6))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .background(Color.purple.opacity(0.5)) // DEBUG
            .border(Color.purple, width: 2) // DEBUG

            Button(action: {
                isPinned.toggle()
                print("📌 Pin clicked!")
            }) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.6))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .background(Color.orange.opacity(0.5)) // DEBUG
            .border(Color.orange, width: 2) // DEBUG
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 0)
        .frame(height: LayoutConstants.appHeaderHeight)
        .background(Color.red.opacity(0.3)) // DEBUG
        .border(Color.red, width: 2) // DEBUG
        .overlay(
            Text("H:\(LayoutConstants.appHeaderHeight)")
                .font(.system(size: 8))
                .foregroundColor(.black)
                .position(x: 200, y: 14)
        )
        .allowsHitTesting(true) // DEBUG: ensure hit testing is enabled
        .zIndex(100) // DEBUG: bring to front
    }
}
