import Foundation
import SwiftGit2

/// Helper to read git information from a repository
public class GitInfoReader {

    /// Git information for a repository
    public struct GitInfo {
        public let repoUrl: String?
        public let currentBranch: String?
        public let commitHash: String?
        public let isDirty: Bool

        public init(repoUrl: String?, currentBranch: String?, commitHash: String?, isDirty: Bool) {
            self.repoUrl = repoUrl
            self.currentBranch = currentBranch
            self.commitHash = commitHash
            self.isDirty = isDirty
        }
    }

    /// Read git information from a directory
    /// - Parameter path: Path to the directory (can be anywhere in the git repo)
    /// - Returns: GitInfo if the directory is in a git repository, nil otherwise
    public static func readGitInfo(at path: String) -> GitInfo? {
        guard let repo = try? Repository.at(URL(fileURLWithPath: path)) else {
            return nil
        }

        // Get remote URL (origin)
        let repoUrl = getRemoteUrl(repo: repo)

        // Get current branch name
        let currentBranch = getCurrentBranch(repo: repo)

        // Get current commit hash
        let commitHash = getCommitHash(repo: repo)

        // Check if working directory is dirty (has uncommitted changes)
        let isDirty = isWorkingDirectoryDirty(repo: repo)

        return GitInfo(
            repoUrl: repoUrl,
            currentBranch: currentBranch,
            commitHash: commitHash,
            isDirty: isDirty
        )
    }

    // MARK: - Private Helpers

    private static func getRemoteUrl(repo: Repository) -> String? {
        // Try to get origin remote
        guard let remote = try? repo.remote(named: "origin") else {
            return nil
        }
        return remote.URL
    }

    private static func getCurrentBranch(repo: Repository) -> String? {
        guard let head = try? repo.HEAD(),
              case let .branch(branch) = head else {
            return nil
        }

        // Extract branch name from full reference
        // e.g., "refs/heads/main" -> "main"
        let branchName = branch.name
        if branchName.hasPrefix("refs/heads/") {
            return String(branchName.dropFirst("refs/heads/".count))
        }
        return branchName
    }

    private static func getCommitHash(repo: Repository) -> String? {
        guard let head = try? repo.HEAD() else {
            return nil
        }

        // Get the OID (Object ID) of the HEAD commit
        let oid = head.oid
        return oid.description
    }

    private static func isWorkingDirectoryDirty(repo: Repository) -> Bool {
        // Check if there are any uncommitted changes
        // This includes both staged and unstaged changes
        guard let statusEntries = try? repo.statusEntries() else {
            return false
        }

        // If there are any status entries, the working directory is dirty
        return statusEntries.count > 0
    }
}
