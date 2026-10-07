import Foundation

/// Every project the person can see, opened once and kept open: what the sidebar lists.
public actor ProjectLibrary {
    public struct Entry: Identifiable, Sendable {
        public var id: String { "\(folderKey)/\(found.relativePath)" }
        public let folderKey: String
        public let found: FoundProject
        public var state: State
        public var workspace: Workspace?
        /// The ready beads read when the project was counted: Ready shows these without asking again.
        public var ready: [Bead] = []
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
        // projects open side by side: the engine serializes calls per project, not across them
        let engine = self.engine
        let opened = await withTaskGroup(of: (Int, Entry).self) { group in
            for (i, found) in projects.enumerated() {
                group.addTask {
                    var entry = Entry(folderKey: folderKey, found: found, state: .opening, workspace: nil)
                    switch found.kind {
                    case .legacy: entry.state = .legacy
                    case .server: entry.state = .server
                    case .embedded:
                        do {
                            let ws = try Workspace(grantedFolder: access, relativePath: found.relativePath, engine: engine)
                            entry.workspace = ws
                            (entry.state, entry.ready) = try await Self.stateAndReady(of: ws)
                        } catch let error as BeadsError {
                            entry.state = .failed(error)
                        } catch {
                            entry.state = .failed(.beads("\(error)"))
                        }
                    }
                    return (i, entry)
                }
            }
            var out: [(Int, Entry)] = []
            for await e in group { out.append(e) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        entries += opened
    }

    /// Runs `read` on every open project at once and gathers the answers in project order.
    func eachOpen<T: Sendable>(_ read: @escaping @Sendable (Entry, Workspace) async -> [T]) async -> [T] {
        let open = entries.compactMap { e -> (Int, Entry, Workspace)? in
            guard case .ready = e.state, let ws = e.workspace else { return nil }
            return (entries.firstIndex { $0.id == e.id } ?? 0, e, ws)
        }
        let parts = await withTaskGroup(of: (Int, [T]).self) { group in
            for (i, e, ws) in open { group.addTask { (i, await read(e, ws)) } }
            var out: [(Int, [T])] = []
            for await p in group { out.append(p) }
            return out
        }
        return parts.sorted { $0.0 < $1.0 }.flatMap(\.1)
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
        do {
            (entries[i].state, entries[i].ready) = try await Self.stateAndReady(of: ws)
        } catch {
            // a project that stops opening says why (busy, gone) instead of keeping old counts
            entries[i].state = .failed(error)
            entries[i].ready = []
        }
    }

    /// Brings an older project up to this app's beads. Only after the person said yes.
    public func upgrade(_ id: String) async {
        guard let i = entries.firstIndex(where: { $0.id == id }), let ws = entries[i].workspace else { return }
        do {
            _ = try await ws.migrate()
            (entries[i].state, entries[i].ready) = try await Self.stateAndReady(of: ws)
        } catch {
            entries[i].state = .failed(error)
        }
    }

    /// Whether an open project has any bead at all, open or closed: "No Beads Yet" versus
    /// "Nothing Ready". One row is asked for.
    public func hasBeads(_ id: String) async -> Bool {
        guard let entry = entries.first(where: { $0.id == id }), let ws = entry.workspace else { return false }
        if !entry.ready.isEmpty { return true }
        return !((try? await ws.list(BeadFilter(limit: 1, includeClosed: true)).beads) ?? []).isEmpty
    }

    public func remove(folderKey: String) async {
        for entry in entries where entry.folderKey == folderKey { await entry.workspace?.close() }
        entries.removeAll { $0.folderKey == folderKey }
    }

    /// Ready beads across every open project, each with its project, in priority order. Reads
    /// nothing: these are the beads each project's last count returned.
    public func readyEverywhere() -> [(project: Entry, bead: Bead)] {
        var out: [(Entry, Bead)] = []
        for entry in entries {
            guard case .ready = entry.state else { continue }
            out += entry.ready.map { (entry, $0) }
        }
        return out.sorted { a, b in
            a.1.priority != b.1.priority ? a.1.priority < b.1.priority : a.1.createdAt < b.1.createdAt
        }
    }

    static func state(of ws: Workspace) async throws(BeadsError) -> State {
        try await stateAndReady(of: ws).0
    }

    /// Opens (read-only) and, when ready, reads the ready work once: its count for the sidebar,
    /// its rows for Ready.
    static func stateAndReady(of ws: Workspace) async throws(BeadsError) -> (State, [Bead]) {
        switch try await ws.open() {
        case .ready:
            let beads = try await ws.ready(limit: 0).beads
            return (.ready(readyCount: beads.count), beads)
        case .needsMigration(let db, let app):
            return (.needsMigration(dbVersion: db, appVersion: app), [])
        case .needsNewerApp(let db, let app):
            return (.needsNewerApp(dbVersion: db, appVersion: app), [])
        }
    }

    /// Beads in progress in every open project, with their claims.
    public func workingEverywhere() async -> [(projectID: String, project: String, bead: Bead)] {
        let out: [(String, String, Bead)] = await eachOpen { entry, ws in
            ((try? await ws.working()) ?? []).map { (entry.id, entry.found.name, $0) }
        }
        return out.sorted { ($0.2.startedAt ?? $0.2.updatedAt) > ($1.2.startedAt ?? $1.2.updatedAt) }
    }

    public func workspace(_ id: String) -> Workspace? { entries.first { $0.id == id }?.workspace }

    public var totalReady: Int {
        entries.reduce(0) { sum, e in
            if case .ready(let n) = e.state { return sum + n }
            return sum
        }
    }
}
