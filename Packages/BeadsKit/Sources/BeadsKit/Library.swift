import Foundation

/// Every project the person can see, opened once and kept open: what the sidebar lists.
public actor ProjectLibrary {
    public struct Entry: Identifiable, Sendable {
        public var id: String { "\(folderKey)/\(found.relativePath)" }
        public let folderKey: String
        public let found: FoundProject
        public var state: State
        public var workspace: Workspace?
    }

    public enum State: Equatable, Sendable {
        case opening
        case ready(readyCount: Int)
        case needsMigration(dbVersion: Int, appVersion: Int)
        case needsNewerApp(dbVersion: Int, appVersion: Int)
        /// beads before 1.0: bd 1.x has to convert it first.
        case legacy
        /// beads on a Dolt SQL server: not readable from the folder.
        case server
        case failed(BeadsError)
    }

    private let engine: any BeadsEngine
    private(set) var entries: [Entry] = []

    public init(engine: any BeadsEngine) { self.engine = engine }

    public var all: [Entry] { entries }

    /// Opens every embedded project under one granted folder. Old and server projects are
    /// listed with their state and never opened.
    public func add(folderKey: String, access: any FolderAccess, projects: [FoundProject]) async {
        for found in projects {
            var entry = Entry(folderKey: folderKey, found: found, state: .opening, workspace: nil)
            switch found.kind {
            case .legacy: entry.state = .legacy
            case .server: entry.state = .server
            case .embedded:
                do {
                    let ws = try Workspace(grantedFolder: access, relativePath: found.relativePath, engine: engine)
                    entry.workspace = ws
                    entry.state = try await Self.state(of: ws)
                } catch {
                    entry.state = .failed(error)
                }
            }
            entries.append(entry)
        }
    }

    /// What each found project would show, without keeping anything open: for the sheet that
    /// lists a new folder's projects before the person picks them.
    public func preview(access: any FolderAccess, projects: [FoundProject]) async -> [String: State] {
        var out: [String: State] = [:]
        for found in projects {
            switch found.kind {
            case .legacy: out[found.relativePath] = .legacy
            case .server: out[found.relativePath] = .server
            case .embedded:
                do {
                    let ws = try Workspace(grantedFolder: access, relativePath: found.relativePath, engine: engine)
                    out[found.relativePath] = try await Self.state(of: ws)
                    await ws.close()
                } catch {
                    out[found.relativePath] = .failed(error)
                }
            }
        }
        return out
    }

    /// Re-counts one project (after a change signal or a write).
    public func refresh(_ id: String) async {
        guard let i = entries.firstIndex(where: { $0.id == id }), let ws = entries[i].workspace else { return }
        entries[i].state = (try? await Self.state(of: ws)) ?? entries[i].state
    }

    public func remove(folderKey: String) async {
        for entry in entries where entry.folderKey == folderKey { await entry.workspace?.close() }
        entries.removeAll { $0.folderKey == folderKey }
    }

    /// Ready beads across every open project, each with its project, in priority order.
    public func readyEverywhere() async -> [(project: Entry, bead: Bead)] {
        var out: [(Entry, Bead)] = []
        for entry in entries {
            guard case .ready = entry.state, let ws = entry.workspace,
                  let page = try? await ws.ready(limit: 0) else { continue }
            out += page.beads.map { (entry, $0) }
        }
        return out.sorted { a, b in
            a.1.priority != b.1.priority ? a.1.priority < b.1.priority : a.1.createdAt < b.1.createdAt
        }
    }

    static func state(of ws: Workspace) async throws(BeadsError) -> State {
        switch try await ws.open() {
        case .ready:
            return .ready(readyCount: try await ws.ready(limit: 0).beads.count)
        case .needsMigration(let db, let app):
            return .needsMigration(dbVersion: db, appVersion: app)
        case .needsNewerApp(let db, let app):
            return .needsNewerApp(dbVersion: db, appVersion: app)
        }
    }

    public var totalReady: Int {
        entries.reduce(0) { sum, e in
            if case .ready(let n) = e.state { return sum + n }
            return sum
        }
    }
}
