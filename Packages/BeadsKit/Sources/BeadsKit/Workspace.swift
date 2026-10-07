import Foundation

/// Access to a folder the person chose. The app adapts BookmarkManager (security-scoped
/// bookmarks); tests pass a plain folder.
public protocol FolderAccess: Sendable {
    /// Starts access and returns the folder, or nil if the bookmark no longer resolves.
    func start() -> URL?
    func stop()
}

/// A folder outside the sandbox (tests, previews): access is always granted.
public struct PlainFolder: FolderAccess {
    public let url: URL
    public init(_ url: URL) { self.url = url }
    public func start() -> URL? { url }
    public func stop() {}
}

/// Where a project stands when it is opened.
public enum OpenState: Equatable, Sendable {
    case ready
    /// Older than this app's beads: reading needs a migration the person allows.
    case needsMigration(dbVersion: Int, appVersion: Int)
    /// Written by a newer beads: this app reads nothing until it is updated.
    case needsNewerApp(dbVersion: Int, appVersion: Int)
}

/// One open project. Access to its folder starts at open and stops at close; every call
/// goes through the engine with this project's handle.
public actor Workspace {
    public nonisolated let project: Project
    private let engine: any BeadsEngine
    private let access: any FolderAccess
    private var handle: Int64?
    private var accessing = false

    /// `relativePath` is the project's .beads folder inside the granted folder.
    public init(grantedFolder access: any FolderAccess, relativePath: String, engine: any BeadsEngine) throws(BeadsError) {
        guard let root = access.start() else { throw .noAccess("the folder bookmark no longer resolves") }
        access.stop()
        self.project = Project(beadsDir: root.appending(path: relativePath, directoryHint: .isDirectory))
        self.access = access
        self.engine = engine
    }

    /// Opens read-only. Never migrates: an older or newer schema comes back as a state.
    public func open() throws(BeadsError) -> OpenState {
        try startAccess()
        var request = EngineRequest(op: "open")
        request.beadsDir = project.beadsDir.path
        do {
            let response = try engine.send(request)
            handle = response.handle
            return .ready
        } catch .schemaBehind(let db, let app, _) {
            return .needsMigration(dbVersion: db, appVersion: app)
        } catch .schemaAhead(let db, let app, _) {
            return .needsNewerApp(dbVersion: db, appVersion: app)
        }
    }

    /// Brings an older project up to this app's schema. Call only after the person said yes:
    /// a bd older than this app refuses the project afterwards.
    public func migrate() throws(BeadsError) -> OpenState {
        try startAccess()
        var request = EngineRequest(op: "migrate")
        request.beadsDir = project.beadsDir.path
        _ = try engine.send(request)
        return try open()
    }

    public func close() {
        if let handle { _ = try? engine.send(EngineRequest(op: "close", handle: handle)) }
        handle = nil
        if accessing { access.stop() }
        accessing = false
    }

    var isOpen: Bool { handle != nil }

    /// Runs one request against the open project.
    func send(_ build: (inout EngineRequest) -> Void, op: String) throws(BeadsError) -> EngineResponse {
        guard let handle else { throw .noHandle("open the project first") }
        var request = EngineRequest(op: op, handle: handle)
        build(&request)
        return try engine.send(request)
    }

    private func startAccess() throws(BeadsError) {
        guard !accessing else { return }
        guard access.start() != nil else { throw .noAccess("the folder bookmark no longer resolves") }
        accessing = true
    }
}
