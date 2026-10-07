import Foundation

/// Where the app last read a project's audit log. beads pages the log by (time, id), so a
/// cursor never skips or repeats an event. Codable so the app keeps one per project.
public struct EventCursor: Hashable, Sendable, Codable {
    public let at: Date
    public let id: String

    public init(at: Date, id: String) {
        self.at = at
        self.id = id
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(at.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)), forKey: .at)
        try c.encode(id, forKey: .id)
    }

    enum CodingKeys: String, CodingKey { case at, id }
}

/// One change from beads' audit log: every bd or beadster write records one.
public struct AuditEvent: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let beadID: String
    public let kind: String
    public let actor: String
    public let oldValue: String?
    public let newValue: String?
    public let comment: String?
    public let at: Date

    enum CodingKeys: String, CodingKey {
        case id, actor, comment
        case beadID = "issue_id", kind = "event_type", oldValue = "old_value", newValue = "new_value", at = "created_at"
    }
}

extension AuditEvent {
    /// One line for a person: who did what. Status values read as words, not wire values.
    public var summary: String {
        func word(_ v: String?) -> String { (v ?? "").replacingOccurrences(of: "_", with: " ") }
        switch kind {
        case "created": return "\(actor) created it"
        case "claimed": return "\(actor) claimed it"
        case "closed": return "\(actor) closed it"
        case "reopened": return "\(actor) reopened it"
        case "commented": return "\(actor) commented"
        case "status_changed": return "\(actor) set \(word(newValue))"
        // beads writes a sentence ("Added dependency: a parent-child b") or nothing here, so the
        // other end is named only when the value is a bare word
        case "dependency_added": return "\(actor) added a link" + bare(newValue).map { " to \($0)" }.orEmpty
        case "dependency_removed": return "\(actor) removed a link" + bare(oldValue).map { " to \($0)" }.orEmpty
        case "label_added": return "\(actor) added " + (bare(newValue).map { "the label \($0)" } ?? "a label")
        case "label_removed": return "\(actor) removed " + (bare(oldValue).map { "the label \($0)" } ?? "a label")
        case "lease_reclaimed": return "the claim by \(actor) ran out"
        default: return "\(actor) \(word(kind))"
        }
    }
}

private func bare(_ value: String?) -> String? {
    guard let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty, !v.contains(" ") else { return nil }
    return v
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

public struct EventPage: Sendable {
    public let events: [AuditEvent]
    public let next: EventCursor?
    public let hasMore: Bool
}

extension Workspace {
    /// The audit log after `cursor` (nil: from the beginning), oldest first.
    public func events(after cursor: EventCursor?, about beadID: String? = nil, limit: Int? = nil) throws(BeadsError) -> EventPage {
        let r = try send({ $0.after = cursor; $0.limit = limit; $0.id = beadID }, op: "events")
        return EventPage(events: r.events ?? [], next: r.next ?? cursor, hasMore: r.hasMore ?? false)
    }
}

/// Turns "something under .beads changed" into the new audit events, in order, once each.
/// The app feeds `changed()` from FSEvents on the bookmarked .beads folder; a burst of file
/// events (one bd write touches several files) costs one read.
public actor LiveFeed {
    private let workspace: Workspace
    private var cursor: EventCursor?
    private var pending = false
    private var reading = false
    private let continuation: AsyncStream<[AuditEvent]>.Continuation
    public nonisolated let updates: AsyncStream<[AuditEvent]>

    /// Starts after `cursor`: pass the saved one, or nil to read only what happens from now on.
    public init(workspace: Workspace, after cursor: EventCursor?) {
        self.workspace = workspace
        self.cursor = cursor
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// With no saved cursor, skip the history: the feed is about what happens next.
    public func startAtNow() async throws(BeadsError) {
        guard cursor == nil else { return }
        var page = try await workspace.events(after: nil)
        while page.hasMore { page = try await workspace.events(after: page.next) }
        cursor = page.next
    }

    public var position: EventCursor? { cursor }

    /// A file under .beads changed. Reads everything new (all pages) and yields it once.
    public func changed() async {
        pending = true
        guard !reading else { return }
        reading = true
        defer { reading = false }
        while pending {
            pending = false
            var batch: [AuditEvent] = []
            do {
                var page = try await workspace.events(after: cursor)
                batch += page.events
                cursor = page.next
                while page.hasMore {
                    page = try await workspace.events(after: cursor)
                    batch += page.events
                    cursor = page.next
                }
            } catch {
                continue // a busy or half-written project: the next change signal reads again
            }
            if !batch.isEmpty { continuation.yield(batch) }
        }
    }

    public func finish() { continuation.finish() }
}
