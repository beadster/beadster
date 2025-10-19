import Foundation

/// Helper to read git information by parsing .git files directly (sandbox-safe)
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
        // Find .git directory
        guard let gitDir = findGitDirectory(from: path) else {
            return nil
        }

        // Get current branch name
        let currentBranch = readCurrentBranch(gitDir: gitDir)

        // Get commit hash for current branch
        let commitHash = readCommitHash(gitDir: gitDir, branch: currentBranch)

        // Get remote URL
        let repoUrl = readRemoteUrl(gitDir: gitDir)

        // For now, we can't easily determine dirty status without shell commands
        // This would require comparing index, working tree, and HEAD
        let isDirty = false

        return GitInfo(
            repoUrl: repoUrl,
            currentBranch: currentBranch,
            commitHash: commitHash,
            isDirty: isDirty
        )
    }

    // MARK: - Private Helpers

    private static func findGitDirectory(from path: String) -> URL? {
        var currentPath = URL(fileURLWithPath: path)

        // Walk up directory tree looking for .git
        while currentPath.path != "/" {
            let gitPath = currentPath.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitPath.path) {
                return gitPath
            }
            currentPath = currentPath.deletingLastPathComponent()
        }

        return nil
    }

    private static func readCurrentBranch(gitDir: URL) -> String? {
        let headPath = gitDir.appendingPathComponent("HEAD")

        guard let headContent = try? String(contentsOf: headPath, encoding: .utf8) else {
            return nil
        }

        // HEAD format: "ref: refs/heads/main\n"
        let trimmed = headContent.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }

        // Detached HEAD - return nil
        return nil
    }

    private static func readCommitHash(gitDir: URL, branch: String?) -> String? {
        guard let branch = branch else {
            return nil
        }

        let refPath = gitDir.appendingPathComponent("refs/heads/\(branch)")

        guard let commitHash = try? String(contentsOf: refPath, encoding: .utf8) else {
            // Try packed-refs if file doesn't exist
            return readPackedRef(gitDir: gitDir, refName: "refs/heads/\(branch)")
        }

        return commitHash.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readPackedRef(gitDir: URL, refName: String) -> String? {
        let packedRefsPath = gitDir.appendingPathComponent("packed-refs")

        guard let content = try? String(contentsOf: packedRefsPath, encoding: .utf8) else {
            return nil
        }

        // Format: "hash refs/heads/branch"
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let parts = trimmed.components(separatedBy: .whitespaces)
            if parts.count >= 2 && parts[1] == refName {
                return parts[0]
            }
        }

        return nil
    }

    private static func readRemoteUrl(gitDir: URL) -> String? {
        let configPath = gitDir.appendingPathComponent("config")

        guard let content = try? String(contentsOf: configPath, encoding: .utf8) else {
            return nil
        }

        // Parse INI-style config
        var inRemoteOrigin = false

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for [remote "origin"] section
            if trimmed == "[remote \"origin\"]" {
                inRemoteOrigin = true
                continue
            }

            // Exit section if we hit another [section]
            if trimmed.hasPrefix("[") {
                inRemoteOrigin = false
                continue
            }

            // Look for url = ... in remote origin section
            if inRemoteOrigin && trimmed.hasPrefix("url = ") {
                return String(trimmed.dropFirst("url = ".count))
            }
        }

        return nil
    }
}
