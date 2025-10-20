//
//  AppConfig.swift
//  Beadster
//
//  Global configuration for app features
//

import Foundation

enum AppConfig {
    // MARK: - Feature Flags

    /// Enable cloud sync features (authentication, sync daemon, API calls)
    /// Set to false for local-only App Store v1 release
    static let cloudSyncEnabled = false

    /// Enable GitHub integration UI
    /// Set to false for App Store v1 release
    static let githubIntegrationEnabled = false

    /// Show debug colors on UI components (borders and backgrounds)
    /// Set to true during development to visualize component boundaries
    static let showDebugColors = false

    // MARK: - Computed Properties

    /// Show authentication/account UI
    static var showAccountUI: Bool {
        cloudSyncEnabled
    }

    /// Show sync status footer
    static var showSyncStatus: Bool {
        cloudSyncEnabled
    }

    /// Enable sync daemon startup
    static var enableSyncDaemon: Bool {
        cloudSyncEnabled
    }

    /// Show GitHub-related features
    static var showGitHubFeatures: Bool {
        githubIntegrationEnabled
    }
}
