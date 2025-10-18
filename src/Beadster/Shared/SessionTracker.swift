import Foundation

public struct SessionInfo {
    public let sessionId: String
    public let client: String
    public let projectName: String?
    public let timestamp: Date
}

public class SessionTracker {
    private let homeDir: String

    public init() {
        self.homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Get current session ID from statsig file
    public func getCurrentSession() -> SessionInfo? {
        let statsigPath = "\(homeDir)/.claude/statsig"

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: statsigPath) else {
            return nil
        }

        // Find statsig.session_id.* file
        guard let sessionFile = files.first(where: { $0.hasPrefix("statsig.session_id.") }) else {
            return nil
        }

        let fullPath = "\(statsigPath)/\(sessionFile)"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = json["sessionID"] as? String else {
            return nil
        }

        // Detect client (claude-code sets CLAUDECODE env var)
        let client = ProcessInfo.processInfo.environment["CLAUDECODE"] != nil ? "claude-code" : "cli"

        // Get project name from current directory
        let cwd = FileManager.default.currentDirectoryPath
        let projectName = URL(fileURLWithPath: cwd).lastPathComponent

        return SessionInfo(
            sessionId: sessionId,
            client: client,
            projectName: projectName,
            timestamp: Date()
        )
    }

    /// Find session for a given issue creation time by checking project logs
    public func findSessionForIssue(createdAt: Int, issueTitle: String) -> SessionInfo? {
        let projectsPath = "\(homeDir)/.claude/projects"

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(atPath: projectsPath) else {
            return nil
        }

        // Convert unix timestamp to Date
        let issueDate = Date(timeIntervalSince1970: TimeInterval(createdAt))

        // Search all project directories for session logs
        for projectDir in projectDirs {
            let projectPath = "\(projectsPath)/\(projectDir)"

            guard let logFiles = try? FileManager.default.contentsOfDirectory(atPath: projectPath) else {
                continue
            }

            // Check each session log file
            for logFile in logFiles where logFile.hasSuffix(".jsonl") {
                let logPath = "\(projectPath)/\(logFile)"

                guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
                    continue
                }

                // Search for bd create command with this title
                let searchPattern = "bd create \"\(issueTitle)\""
                if content.contains(searchPattern) {
                    // Found it! Extract session info from the log entry
                    if let sessionInfo = parseSessionFromLog(content: content, issueTitle: issueTitle, issueDate: issueDate) {
                        return sessionInfo
                    }
                }
            }
        }

        // Fallback: if issue was created recently (last 10 minutes), use current session
        if Date().timeIntervalSince(issueDate) < 600 {
            return getCurrentSession()
        }

        return nil
    }

    /// Parse session info from project log JSONL
    private func parseSessionFromLog(content: String, issueTitle: String, issueDate: Date) -> SessionInfo? {
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            guard line.contains("bd create \"\(issueTitle)\""),
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Extract session ID
            guard let sessionId = json["sessionId"] as? String else {
                continue
            }

            // Extract project name from cwd
            let projectName: String
            if let cwd = json["cwd"] as? String {
                projectName = URL(fileURLWithPath: cwd).lastPathComponent
            } else {
                projectName = "unknown"
            }

            return SessionInfo(
                sessionId: sessionId,
                client: "claude-code",
                projectName: projectName,
                timestamp: issueDate
            )
        }

        return nil
    }

    /// Add session labels to issue
    public func addSessionLabels(to issue: Issue, beadsDir: String) -> Issue {
        // Check if issue already has session labels
        if issue.labels.contains(where: { $0.hasPrefix("-x-session:") }) {
            return issue // Already has session info
        }

        // Get project name from beads directory
        let projectName = URL(fileURLWithPath: beadsDir).lastPathComponent

        // Skip session tracking for now - too slow
        // TODO: optimize session tracking with caching
        let sessionInfo = getCurrentSession()

        guard let session = sessionInfo else {
            return issue // Can't determine session
        }

        // Use project name from beads directory, not from session
        let finalProjectName = projectName

        // Add system labels with -x- prefix
        var newLabels = issue.labels
        newLabels.append("-x-session:\(session.sessionId)")
        newLabels.append("-x-client:\(session.client)")
        newLabels.append("-x-project:\(finalProjectName)")

        // Create new issue with updated labels and session metadata
        return Issue(
            id: issue.id,
            title: issue.title,
            body: issue.body,
            status: issue.status,
            priority: issue.priority,
            labels: newLabels,
            createdAt: issue.createdAt,
            updatedAt: issue.updatedAt,
            sessionId: session.sessionId,
            client: session.client,
            projectName: finalProjectName
        )
    }
}
