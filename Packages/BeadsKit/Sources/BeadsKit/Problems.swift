import Foundation

/// The beads this app carries, for the words that name it.
public enum BeadsVersion {
    public static let carried = "1.3.1"
    public static let upgradeGuide = URL(string: "https://github.com/gastownhall/beads/blob/main/docs/getting-started/upgrading.md")!
}

/// Why a project (or a folder) shows no beads, in words, with the one thing to do about it.
/// Views draw this and compute nothing.
public struct Problem: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Upgrade the project's database to this app's beads (asked first: older bd stops reading it).
        case upgradeProject
        /// Update beadster in the App Store.
        case updateApp
        /// beads' own upgrade guide.
        case openGuide
        case chooseFolderAgain
        case tryAgain

        /// The button's words.
        public var title: String {
            switch self {
            case .upgradeProject: "Update Project…"
            case .updateApp: "Update beadster"
            case .openGuide: "Open Upgrade Guide"
            case .chooseFolderAgain: "Choose Folder…"
            case .tryAgain: "Try Again"
            }
        }
    }

    public let title: String
    public let symbol: String
    public let message: String
    public let action: Action?
    /// beads' own text, shown small under the message so a report carries it.
    public let detail: String?

    public static func of(_ state: ProjectLibrary.State) -> Problem? {
        switch state {
        case .opening, .ready: return nil
        case .needsMigration:
            return Problem(title: "Made With an Older beads", symbol: "arrow.up.circle",
                           message: "Update this project to beads \(BeadsVersion.carried) to open it here. Agents working on it will need bd \(BeadsVersion.carried) or newer too.",
                           action: .upgradeProject, detail: nil)
        case .needsNewerApp:
            return Problem(title: "Made With a Newer beads", symbol: "arrow.down.app",
                           message: "This project was written by a newer beads than beadster carries. Update beadster to open it.",
                           action: .updateApp, detail: nil)
        case .legacy:
            return Problem(title: "Made With beads Before 1.0", symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                           message: "beads' upgrade guide converts it with bd 1.0 or newer. Then it opens here.",
                           action: .openGuide, detail: nil)
        case .server:
            return Problem(title: "Kept on a Dolt Server", symbol: "server.rack",
                           message: "beadster opens projects whose beads live in their own folder.",
                           action: nil, detail: nil)
        case .failed(let error):
            if case .noAccess = error { return folderLost }
            if case .busy = error {
                return Problem(title: "Project Is Busy", symbol: "lock",
                               message: error.sentence, action: .tryAgain, detail: error.raw)
            }
            return Problem(title: "Could Not Open", symbol: "exclamationmark.triangle",
                           message: "beads could not read this project.", action: .tryAgain, detail: error.raw)
        }
    }

    /// The folder was moved away, deleted, or its access ended.
    public static let folderLost = Problem(title: "Folder Not Found", symbol: "folder.badge.questionmark",
                                           message: "beadster can no longer reach this folder. Choose it again where it is now.",
                                           action: .chooseFolderAgain, detail: nil)

    /// A project that opened and has no beads at all, as opposed to nothing ready.
    public static let noBeadsYet = Problem(title: "No Beads Yet", symbol: "circle.dotted",
                                           message: "Beads made here or by an agent with bd show up at once.",
                                           action: nil, detail: nil)
}

extension BeadsError {
    /// beads' own text.
    public var raw: String {
        switch self {
        case .noBeads(let m), .serverMode(let m), .notFound(let m), .busy(let m), .badRequest(let m),
             .noHandle(let m), .conflict(let m), .claimed(let m), .refused(let m), .noAccess(let m),
             .beads(let m), .undecodable(let m):
            return m
        case .schemaAhead(_, _, let m), .schemaBehind(_, _, let m):
            return m
        }
    }

    /// One calm sentence for a failed write; beads' words when they are the best explanation.
    public var sentence: String {
        switch self {
        case .busy: "Another program is writing to this project. Try again in a moment."
        case .conflict: "Someone changed this bead first. Nothing was written."
        case .claimed: "Someone else has claimed this bead."
        case .noAccess: "beadster can no longer reach this folder. Choose it again in Settings."
        case .schemaAhead: "This project was written by a newer beads than beadster carries."
        case .schemaBehind: "This project needs an update before it can be changed here."
        case .refused(let m), .notFound(let m): m
        default: "beads could not make the change."
        }
    }

    /// What a failed write shows: the sentence, and beads' text under it when it adds something.
    public var report: String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == sentence ? sentence : "\(sentence)\n\(text)"
    }
}
