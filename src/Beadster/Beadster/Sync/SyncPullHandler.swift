//
//  SyncPullHandler.swift
//  Beadster
//
//  Handles pulling changes from cloud and merging with local JSONL
//

import Foundation

class SyncPullHandler {
    /// Pull changes from cloud and apply to local JSONL (source of truth)
    static func pullAndApply(
        projectURL: URL,
        sourceId: String,
        since: Int
    ) async throws -> Int {
        print("🔽 Pulling changes since \(since)...")

        // Get remote changes
        let changes = try await APIClient.shared.pullChanges(sourceId: sourceId, since: since)

        if changes.isEmpty {
            print("  ✓ No changes from cloud")
            return 0
        }

        print("⬇️  Applying \(changes.count) change(s)...")

        // Read current JSONL (source of truth)
        var localIssues = try JSONLManager.readIssues(from: projectURL)
        var appliedCount = 0

        // Apply each change
        for cloudIssue in changes {
            // Check if issue exists locally in JSONL
            if let localIndex = localIssues.firstIndex(where: { $0.id == cloudIssue.id }) {
                // Issue exists - merge changes
                let localIssue = localIssues[localIndex]

                // Use cloud version if it's newer
                if cloudIssue.updatedAt > localIssue.updatedAt {
                    print("  🔄 Updating: \(cloudIssue.title)")
                    localIssues[localIndex] = cloudIssue
                    appliedCount += 1
                } else {
                    print("  ⊘ Skipping older version: \(cloudIssue.title)")
                }
            } else {
                // New issue from cloud - add to JSONL
                print("  ➕ Adding new issue from cloud: \(cloudIssue.title)")
                localIssues.append(cloudIssue)
                appliedCount += 1
            }
        }

        // Write updated issues back to JSONL (source of truth)
        if appliedCount > 0 {
            try JSONLManager.writeIssues(localIssues, to: projectURL)
            print("  ✅ Applied \(appliedCount) change(s) to JSONL")
        } else {
            print("  ✓ No changes applied")
        }

        return appliedCount
    }
}
