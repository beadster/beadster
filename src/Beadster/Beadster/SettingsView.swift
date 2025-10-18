//
//  SettingsView.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .frame(width: 500, height: 300)
        }
        .padding()
    }
}

struct GeneralSettings: View {
    var body: some View {
        Form {
            Section("API") {
                HStack {
                    Text("Endpoint:")
                    Spacer()
                    Text("beadster-dev-app.systemoperator.workers.dev")
                        .foregroundColor(.secondary)
                        .font(.caption.monospaced())
                }

                HStack {
                    Text("Token:")
                    Spacer()
                    Text("dev-token-placeholder")
                        .foregroundColor(.secondary)
                        .font(.caption.monospaced())
                }
            }

            Section("Sync") {
                HStack {
                    Text("Interval:")
                    Spacer()
                    Text("5 minutes")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Last Sync:")
                    Spacer()
                    Text("Never")
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Text("POC version - auth and sync coming soon")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
}
