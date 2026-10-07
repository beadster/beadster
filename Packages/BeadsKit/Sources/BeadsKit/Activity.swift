import Foundation

/// One change for the Activity list: the audit event, its project, and the bead's title.
public struct ActivityItem: Identifiable, Hashable, Sendable {
    public var id: String { "\(projectID)|\(event.id)" }
    public let projectID: String
    public let project: String
    public let event: AuditEvent
    public let title: String?
    /// How many changes this row stands for: a run of the same change by the same actor in the
    /// same project within a minute (an import, a batch close) reads as one row.
    public var count: Int = 1

    public init(projectID: String, project: String, event: AuditEvent, title: String?, count: Int = 1) {
        self.projectID = projectID
        self.project = project
        self.event = event
        self.title = title
        self.count = count
    }

    /// The row's words: the event's own summary, or the run in one line.
    public var summary: String {
        guard count > 1 else { return event.summary }
        let n = count.formatted()
        switch event.kind {
        case "created": return "\(event.actor) created \(n) beads"
        case "closed": return "\(event.actor) closed \(n) beads"
        case "updated": return "\(event.actor) changed \(n) beads"
        default: return "\(event.actor) made \(n) changes"
        }
    }

    /// Collapses runs (input newest first): same project, actor and kind, each within a minute
    /// of the one before.
    public static func grouped(_ items: [ActivityItem]) -> [ActivityItem] {
        var out: [ActivityItem] = []
        var last: ActivityItem?
        for item in items {
            if var run = out.last, let prev = last, run.projectID == item.projectID,
               run.event.actor == item.event.actor, run.event.kind == item.event.kind,
               abs(prev.event.at.timeIntervalSince(item.event.at)) <= 60 {
                run.count += 1
                out[out.count - 1] = run
            } else {
                out.append(item)
            }
            last = item
        }
        return out
    }
}

extension Workspace {
    /// The audit log since a moment (every page), oldest first.
    public func events(since: Date) throws(BeadsError) -> [AuditEvent] {
        var cursor: EventCursor? = EventCursor(at: since, id: "")
        var out: [AuditEvent] = []
        repeat {
            let page = try events(after: cursor)
            out += page.events
            cursor = page.next
            if !page.hasMore { break }
        } while true
        return out
    }

    /// Titles for these beads in one list call (closed and gates included).
    public func titles(of ids: Set<String>) throws(BeadsError) -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        let rows = try send({ $0.all = true; $0.includeGates = true; $0.limit = 0 }, op: "list").issues ?? []
        return Dictionary(rows.filter { ids.contains($0.id) }.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
    }
}

extension ProjectLibrary {
    /// Every change since `since` in every open project, newest first.
    public func activity(since: Date) async -> [ActivityItem] {
        let items: [ActivityItem] = await eachOpen { entry, ws in
            guard let events = try? await ws.events(since: since), !events.isEmpty else { return [] }
            let titles = (try? await ws.titles(of: Set(events.map(\.beadID)))) ?? [:]
            return events.map { ActivityItem(projectID: entry.id, project: entry.found.name, event: $0, title: titles[$0.beadID]) }
        }
        return ActivityItem.grouped(items.sorted { $0.event.at > $1.event.at })
    }
}

extension ProjectLibrary {
    /// Every project's memories (bd remember), project by project, keys in order.
    public func memoriesEverywhere() async -> [(projectID: String, project: String, memory: Memory)] {
        await eachOpen { entry, ws in
            ((try? await ws.memories()) ?? []).map { (entry.id, entry.found.name, $0) }
        }
    }
}
