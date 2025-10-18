//
//  BeadsterApp.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import SwiftUI

@main
struct BeadsterApp: App {
    @StateObject private var syncDaemon = SyncDaemon.shared

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
        }
    }

    init() {
        // start sync daemon on app launch
        Task { @MainActor in
            SyncDaemon.shared.start()
        }
    }
}
