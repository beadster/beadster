import Foundation

/// The door to beads' Go code. The app passes BeadsFFI (BeadsBridge); tests pass a fake.
public protocol BeadsEngine: Sendable {
    func call(_ request: Data) -> Data
}

/// What beads said went wrong. The raw beads text is kept in every case.
public enum BeadsError: Error, Equatable, Sendable {
    case noBeads(String)
    case serverMode(String)
    /// The project was written by a newer beads than this app carries. Nothing is read.
    case schemaAhead(dbVersion: Int, appVersion: Int, message: String)
    /// The project is older than this app's beads. Opening needs a migration only the person can allow.
    case schemaBehind(dbVersion: Int, appVersion: Int, message: String)
    case notFound(String)
    /// Another writer still holds the project.
    case busy(String)
    case badRequest(String)
    case noHandle(String)
    /// A compare-and-set guard did not hold: someone changed the bead first. Nothing was written.
    case conflict(String)
    /// The bead is claimed by someone else.
    case claimed(String)
    /// beads refused the change itself (closing a blocked bead, a cycle, a release with no claim).
    case refused(String)
    /// The folder bookmark no longer gives access (moved, deleted, access revoked).
    case noAccess(String)
    case beads(String)
    case undecodable(String)
}

/// One request, field for field the Go engine's Request.
struct EngineRequest: Encodable {
    var op: String
    var handle: Int64?
    var beadsDir: String?
    var id: String?
    var status: String?
    var limit: Int?
    var actor: String?
    var title: String?
    var description: String?
    var priority: Int?
    var issueType: String?
    var assignee: String?
    var newStatus: String?
    var reason: String?
    var filterType: String?
    var filterAssignee: String?
    var label: String?
    var titleContains: String?
    var design: String?
    var acceptance: String?
    var notes: String?
    var addLabels: [String]?
    var removeLabels: [String]?
    var parent: String?
    var target: String?
    var linkType: String?
    var text: String?
    var key: String?
    var force: Bool?
    var expectedStatus: String?
    var expectedAssignee: String?

    enum CodingKeys: String, CodingKey {
        case op, handle, id, status, limit, actor, title, description, priority, assignee, reason, label
        case design, notes, parent, target, text, key, force
        case beadsDir = "beads_dir", issueType = "issue_type", newStatus = "new_status"
        case filterType = "filter_type", filterAssignee = "filter_assignee", titleContains = "title_contains"
        case acceptance = "acceptance_criteria", addLabels = "add_labels", removeLabels = "remove_labels"
        case linkType = "link_type", expectedStatus = "expected_status", expectedAssignee = "expected_assignee"
    }

    init(op: String, handle: Int64? = nil) {
        self.op = op
        self.handle = handle
    }
}

/// One answer from the Go engine.
struct EngineResponse: Decodable {
    struct Failure: Decodable {
        let code: String
        let message: String
        let dbVersion: Int?
        let binaryVersion: Int?
        enum CodingKeys: String, CodingKey {
            case code, message
            case dbVersion = "db_version", binaryVersion = "binary_version"
        }
    }
    struct ProjectInfo: Decodable {
        let beadsDir: String
        let database: String
        let mode: String
        enum CodingKeys: String, CodingKey {
            case database, mode
            case beadsDir = "beads_dir"
        }
    }

    let error: Failure?
    let handle: Int64?
    let project: ProjectInfo?
    let issues: [Bead]?
    let issue: Bead?
    let details: Bead?
    let hasMore: Bool?
    let changed: Bool?
    let blocked: [BlockedBead]?
    let history: [HistoryEntry]?
    let memories: [String: String]?
    let progress: MoleculeProgress?

    enum CodingKeys: String, CodingKey {
        case error, handle, project, issues, issue, details, changed, blocked, history, memories, progress
        case hasMore = "has_more"
    }
}

extension BeadsError {
    init(_ f: EngineResponse.Failure) {
        switch f.code {
        case "no_beads": self = .noBeads(f.message)
        case "server_mode": self = .serverMode(f.message)
        case "schema_ahead": self = .schemaAhead(dbVersion: f.dbVersion ?? 0, appVersion: f.binaryVersion ?? 0, message: f.message)
        case "schema_behind": self = .schemaBehind(dbVersion: f.dbVersion ?? 0, appVersion: f.binaryVersion ?? 0, message: f.message)
        case "not_found": self = .notFound(f.message)
        case "busy": self = .busy(f.message)
        case "bad_request": self = .badRequest(f.message)
        case "no_handle": self = .noHandle(f.message)
        case "conflict": self = .conflict(f.message)
        case "claimed": self = .claimed(f.message)
        case "refused": self = .refused(f.message)
        default: self = .beads(f.message)
        }
    }
}

extension BeadsEngine {
    func send(_ request: EngineRequest) throws(BeadsError) -> EngineResponse {
        let body: Data
        do { body = try JSONEncoder().encode(request) } catch { throw .badRequest("\(error)") }
        let out = call(body)
        let response: EngineResponse
        do {
            response = try BeadsJSON.decoder().decode(EngineResponse.self, from: out)
        } catch {
            throw .undecodable("\(error) in \(String(decoding: out.prefix(300), as: UTF8.self))")
        }
        if let failure = response.error { throw BeadsError(failure) }
        return response
    }
}
