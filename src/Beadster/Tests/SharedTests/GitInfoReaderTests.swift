//
//  GitInfoReaderTests.swift
//  Beadster
//
//  Unit tests for GitInfoReader
//

import XCTest
@testable import Shared

final class GitInfoReaderTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        // Create a temporary directory for each test
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createGitDirectory(branch: String = "main", commitHash: String = "abc123def456") throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        // Create HEAD
        let headContent = "ref: refs/heads/\(branch)\n"
        try headContent.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        // Create refs/heads directory and branch file (handle branches with slashes)
        let branchFilePath = gitDir.appendingPathComponent("refs/heads/\(branch)")
        let branchFileDir = branchFilePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: branchFileDir, withIntermediateDirectories: true)
        try "\(commitHash)\n".write(to: branchFilePath, atomically: true, encoding: .utf8)

        // Create config with remote origin
        let configContent = """
        [core]
        \trepositoryformatversion = 0
        \tfilemode = true
        [remote "origin"]
        \turl = https://github.com/user/repo.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        [branch "main"]
        \tremote = origin
        \tmerge = refs/heads/main
        """
        try configContent.write(to: gitDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    }

    private func createPackedRefsGit(branch: String = "main", commitHash: String = "packed123def456") throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        // Create HEAD
        let headContent = "ref: refs/heads/\(branch)\n"
        try headContent.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        // Create packed-refs instead of individual ref files
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(commitHash) refs/heads/\(branch)
        abc123def456 refs/heads/other-branch
        # comment line
        """
        try packedRefsContent.write(to: gitDir.appendingPathComponent("packed-refs"), atomically: true, encoding: .utf8)

        // Create config
        let configContent = """
        [remote "origin"]
        \turl = git@github.com:user/repo.git
        """
        try configContent.write(to: gitDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    }

    // MARK: - Tests

    func testReadGitInfoBasic() throws {
        try createGitDirectory()

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNotNil(gitInfo, "Should read git info from directory with .git")
        XCTAssertEqual(gitInfo?.currentBranch, "main", "Should read current branch")
        XCTAssertEqual(gitInfo?.commitHash, "abc123def456", "Should read commit hash")
        XCTAssertEqual(gitInfo?.repoUrl, "https://github.com/user/repo.git", "Should read remote URL")
        XCTAssertEqual(gitInfo?.isDirty, false, "isDirty should be false (not implemented)")
    }

    func testReadGitInfoFromSubdirectory() throws {
        try createGitDirectory()

        // Create nested subdirectories
        let subDir = tempDir.appendingPathComponent("src/components")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let gitInfo = GitInfoReader.readGitInfo(at: subDir.path)

        XCTAssertNotNil(gitInfo, "Should find .git directory by walking up tree")
        XCTAssertEqual(gitInfo?.currentBranch, "main", "Should read branch from parent .git")
        XCTAssertEqual(gitInfo?.commitHash, "abc123def456", "Should read commit hash from parent .git")
    }

    func testReadGitInfoDifferentBranch() throws {
        try createGitDirectory(branch: "feature/new-feature", commitHash: "feature123abc")

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNotNil(gitInfo, "Should read git info")
        XCTAssertEqual(gitInfo?.currentBranch, "feature/new-feature", "Should handle branch names with slashes")
        XCTAssertEqual(gitInfo?.commitHash, "feature123abc", "Should read correct commit hash for branch")
    }

    func testReadGitInfoDetachedHead() throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        // Create detached HEAD (contains commit hash directly, not ref)
        let headContent = "abc123def456789\n"
        try headContent.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNotNil(gitInfo, "Should read git info even with detached HEAD")
        XCTAssertNil(gitInfo?.currentBranch, "Should return nil for detached HEAD")
        XCTAssertNil(gitInfo?.commitHash, "Should return nil commit hash when no branch")
    }

    func testReadGitInfoPackedRefs() throws {
        try createPackedRefsGit(branch: "main", commitHash: "packed123def456")

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNotNil(gitInfo, "Should read git info from packed-refs")
        XCTAssertEqual(gitInfo?.currentBranch, "main", "Should read branch from HEAD")
        XCTAssertEqual(gitInfo?.commitHash, "packed123def456", "Should read commit hash from packed-refs")
        XCTAssertEqual(gitInfo?.repoUrl, "git@github.com:user/repo.git", "Should read SSH remote URL")
    }

    func testReadGitInfoPackedRefsWithDifferentBranch() throws {
        try createPackedRefsGit(branch: "develop", commitHash: "develop789xyz")

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNotNil(gitInfo, "Should read git info")
        XCTAssertEqual(gitInfo?.currentBranch, "develop", "Should read correct branch")
        XCTAssertEqual(gitInfo?.commitHash, "develop789xyz", "Should find correct commit in packed-refs")
    }

    func testReadGitInfoNoGitDirectory() {
        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNil(gitInfo, "Should return nil when no .git directory exists")
    }

    func testReadGitInfoInvalidPath() {
        let gitInfo = GitInfoReader.readGitInfo(at: "/nonexistent/path/that/does/not/exist")

        XCTAssertNil(gitInfo, "Should return nil for invalid path")
    }

    func testReadGitInfoNoConfig() throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        // Create HEAD
        let headContent = "ref: refs/heads/main\n"
        try headContent.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        // Create branch ref
        let refsHeadsDir = gitDir.appendingPathComponent("refs/heads")
        try FileManager.default.createDirectory(at: refsHeadsDir, withIntermediateDirectories: true)
        try "abc123\n".write(to: refsHeadsDir.appendingPathComponent("main"), atomically: true, encoding: .utf8)

        // No config file

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNotNil(gitInfo, "Should read git info even without config")
        XCTAssertEqual(gitInfo?.currentBranch, "main", "Should read branch")
        XCTAssertEqual(gitInfo?.commitHash, "abc123", "Should read commit")
        XCTAssertNil(gitInfo?.repoUrl, "Should return nil for repoUrl when config missing")
    }

    func testReadGitInfoNoRemoteInConfig() throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let headContent = "ref: refs/heads/main\n"
        try headContent.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let refsHeadsDir = gitDir.appendingPathComponent("refs/heads")
        try FileManager.default.createDirectory(at: refsHeadsDir, withIntermediateDirectories: true)
        try "abc123\n".write(to: refsHeadsDir.appendingPathComponent("main"), atomically: true, encoding: .utf8)

        // Config without remote
        let configContent = """
        [core]
        \trepositoryformatversion = 0
        """
        try configContent.write(to: gitDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNotNil(gitInfo, "Should read git info")
        XCTAssertNil(gitInfo?.repoUrl, "Should return nil for repoUrl when no remote in config")
    }

    func testReadGitInfoMultipleRemotes() throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let headContent = "ref: refs/heads/main\n"
        try headContent.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let refsHeadsDir = gitDir.appendingPathComponent("refs/heads")
        try FileManager.default.createDirectory(at: refsHeadsDir, withIntermediateDirectories: true)
        try "abc123\n".write(to: refsHeadsDir.appendingPathComponent("main"), atomically: true, encoding: .utf8)

        // Config with multiple remotes
        let configContent = """
        [remote "origin"]
        \turl = https://github.com/user/repo.git
        [remote "upstream"]
        \turl = https://github.com/original/repo.git
        """
        try configContent.write(to: gitDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNotNil(gitInfo, "Should read git info")
        XCTAssertEqual(gitInfo?.repoUrl, "https://github.com/user/repo.git", "Should read origin remote (first one)")
    }

    func testReadGitInfoNoHEADFile() throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        // No HEAD file

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNotNil(gitInfo, "Should not crash when HEAD missing")
        XCTAssertNil(gitInfo?.currentBranch, "Should return nil branch when HEAD missing")
    }

    func testReadGitInfoEmptyHEAD() throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        // Empty HEAD file
        try "".write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNotNil(gitInfo, "Should not crash with empty HEAD")
        XCTAssertNil(gitInfo?.currentBranch, "Should return nil for empty HEAD")
    }

    func testReadGitInfoWhitespaceInFiles() throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        // HEAD with extra whitespace
        let headContent = "  ref: refs/heads/main  \n\n"
        try headContent.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let refsHeadsDir = gitDir.appendingPathComponent("refs/heads")
        try FileManager.default.createDirectory(at: refsHeadsDir, withIntermediateDirectories: true)

        // Commit hash with whitespace
        try "  abc123def456  \n\n".write(to: refsHeadsDir.appendingPathComponent("main"), atomically: true, encoding: .utf8)

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertNotNil(gitInfo, "Should handle whitespace in files")
        XCTAssertEqual(gitInfo?.currentBranch, "main", "Should trim whitespace from branch name")
        XCTAssertEqual(gitInfo?.commitHash, "abc123def456", "Should trim whitespace from commit hash")
    }

    func testReadGitInfoLongCommitHash() throws {
        let longHash = "1234567890abcdef1234567890abcdef12345678"
        try createGitDirectory(branch: "main", commitHash: longHash)

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertEqual(gitInfo?.commitHash, longHash, "Should handle full 40-character commit hashes")
    }

    func testReadGitInfoShortCommitHash() throws {
        let shortHash = "abc123"
        try createGitDirectory(branch: "main", commitHash: shortHash)

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertEqual(gitInfo?.commitHash, shortHash, "Should handle short commit hashes")
    }

    func testReadGitInfoBranchWithSpecialCharacters() throws {
        // Branch names can contain slashes, hyphens, underscores
        let branchName = "feature/ABC-123_new-feature"
        try createGitDirectory(branch: branchName, commitHash: "special123")

        let gitInfo = GitInfoReader.readGitInfo(at: tempDir.path)

        XCTAssertEqual(gitInfo?.currentBranch, branchName, "Should handle branch names with special characters")
        XCTAssertEqual(gitInfo?.commitHash, "special123", "Should read commit for branch with special chars")
    }
}
