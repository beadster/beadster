//
//  BeadsterApp.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import SwiftUI
import UserNotifications

@main
struct BeadsterApp: App {
    @StateObject private var syncDaemon = SyncDaemon.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Beadster", id: "main") {
            MainView()
                .frame(minWidth: 400, maxWidth: 400, minHeight: 500, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 700)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    init() {
        // initialize auth manager first to set API token (only in cloud mode)
        if AppConfig.cloudSyncEnabled {
            _ = AuthManager.shared
        }

        // start sync daemon on app launch
        // Note: daemon handles file watching in local mode + cloud sync in cloud mode
        Task { @MainActor in
            SyncDaemon.shared.start()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permissions granted")
            } else if let error = error {
                print("❌ Notification permission error: \(error)")
            }
        }
    }
}
