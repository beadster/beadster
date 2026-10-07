// The open sets beads uses: a project can configure its own statuses and types (`bd statuses`,
// `bd types`), so each is the known values beads ships plus `.other` for anything else.
// Switches stay exhaustive; an unknown value is shown as its own word, never dropped.

public enum BeadStatus: Hashable, Sendable, Codable, CustomStringConvertible {
    case open, inProgress, blocked, deferred, closed, pinned, hooked
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "open": self = .open
        case "in_progress": self = .inProgress
        case "blocked": self = .blocked
        case "deferred": self = .deferred
        case "closed": self = .closed
        case "pinned": self = .pinned
        case "hooked": self = .hooked
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .open: "open"
        case .inProgress: "in_progress"
        case .blocked: "blocked"
        case .deferred: "deferred"
        case .closed: "closed"
        case .pinned: "pinned"
        case .hooked: "hooked"
        case .other(let s): s
        }
    }

    public var description: String { rawValue }
    public init(from decoder: Decoder) throws { self.init(rawValue: try decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

public enum BeadType: Hashable, Sendable, Codable, CustomStringConvertible {
    case bug, feature, task, epic, chore, decision, message, molecule, gate, spike, story, milestone
    case other(String)

    static let known: [String: BeadType] = [
        "bug": .bug, "feature": .feature, "task": .task, "epic": .epic, "chore": .chore,
        "decision": .decision, "message": .message, "molecule": .molecule, "gate": .gate,
        "spike": .spike, "story": .story, "milestone": .milestone,
    ]

    public init(rawValue: String) { self = Self.known[rawValue] ?? .other(rawValue) }

    public var rawValue: String {
        if case .other(let s) = self { return s }
        return Self.known.first { $0.value == self }?.key ?? ""
    }

    public var description: String { rawValue }
    public init(from decoder: Decoder) throws { self.init(rawValue: try decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

/// The edge between two beads. `blocks`-like kinds decide readiness; the rest are links.
public enum LinkKind: Hashable, Sendable, Codable, CustomStringConvertible {
    case blocks, parentChild, conditionalBlocks, waitsFor
    case related, relatesTo, discoveredFrom, repliesTo, duplicates, supersedes
    case other(String)

    static let known: [String: LinkKind] = [
        "blocks": .blocks, "parent-child": .parentChild, "conditional-blocks": .conditionalBlocks,
        "waits-for": .waitsFor, "related": .related, "relates-to": .relatesTo,
        "discovered-from": .discoveredFrom, "replies-to": .repliesTo, "duplicates": .duplicates,
        "supersedes": .supersedes,
    ]

    public init(rawValue: String) { self = Self.known[rawValue] ?? .other(rawValue) }

    public var rawValue: String {
        if case .other(let s) = self { return s }
        return Self.known.first { $0.value == self }?.key ?? ""
    }

    /// Whether this edge holds the bead out of Ready.
    public var isBlocking: Bool {
        switch self {
        case .blocks, .conditionalBlocks, .waitsFor: true
        default: false
        }
    }

    public var description: String { rawValue }
    public init(from decoder: Decoder) throws { self.init(rawValue: try decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}
