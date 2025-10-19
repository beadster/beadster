import Foundation

/// Helper to read git information from a repository using git CLI
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
        // Check if this is a git repository
        guard isGitRepository(at: path) else {
            return nil
        }

        // Get remote URL (origin)
        let repoUrl = getRemoteUrl(at: path)

        // Get current branch name
        let currentBranch = getCurrentBranch(at: path)

        // Get current commit hash
        let commitHash = getCommitHash(at: path)

        // Check if working directory is dirty (has uncommitted changes)
        let isDirty = isWorkingDirectoryDirty(at: path)

        return GitInfo(
            repoUrl: repoUrl,
            currentBranch: currentBranch,
            commitHash: commitHash,
            isDirty: isDirty
        )
    }

    // MARK: - Private Helpers

    private static func isGitRepository(at path: String) -> Bool {
        return runGitCommand(["rev-parse", "--git-dir"], in: path) != nil
    }

    private static func getRemoteUrl(at path: String) -> String? {
        return runGitCommand(["config", "--get", "remote.origin.url"], in: path)
    }

    private static func getCurrentBranch(at path: String) -> String? {
        return runGitCommand(["rev-parse", "--abbrev-ref", "HEAD"], in: path)
    }

    private static func getCommitHash(at path: String) -> String? {
        return runGitCommand(["rev-parse", "HEAD"], in: path)
    }

    private static func isWorkingDirectoryDirty(at path: String) -> Bool {
        // Check if there are any uncommitted changes
        let status = runGitCommand(["status", "--porcelain"], in: path)
        return status != nil && !status!.isEmpty
    }

    private static func runGitCommand(_ arguments: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return output?.isEmpty == true ? nil : output
        } catch {
            return nil
        }
    }
}
