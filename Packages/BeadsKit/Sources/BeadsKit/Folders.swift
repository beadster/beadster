import Foundation

/// A project found under a granted folder.
public struct FoundProject: Identifiable, Hashable, Sendable {
    public var id: String { relativePath }
    public let name: String
    /// The .beads folder, relative to the granted folder (what Workspace opens).
    public let relativePath: String
    public let kind: Kind

    public init(name: String, relativePath: String, kind: Kind) {
        self.name = name
        self.relativePath = relativePath
        self.kind = kind
    }

    public enum Kind: Hashable, Sendable {
        /// beads 1.x, embedded Dolt in the repo: beadster opens it.
        case embedded
        /// beads 1.x on a Dolt SQL server: the data is not in the folder.
        case server
        /// beads before 1.0 (SQLite or issues.jsonl only): bd 1.x has to convert it first.
        case legacy
    }
}

/// Finds every project with a .beads folder under a granted folder. Reads directory
/// listings only, never a database, so it is fast and writes nothing.
public enum ProjectScanner {
    /// Folders that never hold a project's own .beads and can be huge.
    static let skipped: Set<String> = [
        "node_modules", ".git", ".build", "build", "dist", "DerivedData", "Pods", "Carthage",
        "vendor", ".venv", "venv", "target", ".next", ".cache", ".Trash", "Library",
    ]

    public static func scan(_ root: URL, maxDepth: Int = 4) -> [FoundProject] {
        var found: [FoundProject] = []
        let root = root.resolvingSymlinksInPath()
        walk(root, root: root, depth: 0, maxDepth: maxDepth, into: &found)
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func walk(_ dir: URL, root: URL, depth: Int, maxDepth: Int, into found: inout [FoundProject]) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            let name = entry.lastPathComponent
            if name == ".beads" {
                if let kind = kind(of: entry) {
                    let parts = entry.resolvingSymlinksInPath().pathComponents
                    let rel = parts.dropFirst(root.pathComponents.count).joined(separator: "/")
                    let projectName = dir == root ? root.lastPathComponent : dir.lastPathComponent
                    found.append(FoundProject(name: projectName, relativePath: rel, kind: kind))
                }
                continue
            }
            if depth < maxDepth, !skipped.contains(name), !(name.hasPrefix(".") && name != ".beads") {
                walk(entry, root: root, depth: depth + 1, maxDepth: maxDepth, into: &found)
            }
        }
    }

    /// What kind of beads lives in this .beads folder, or nil if it holds none.
    static func kind(of beads: URL) -> FoundProject.Kind? {
        let fm = FileManager.default
        func has(_ name: String) -> Bool { fm.fileExists(atPath: beads.appending(path: name).path) }
        if has("embeddeddolt") { return .embedded }
        if let data = try? Data(contentsOf: beads.appending(path: "metadata.json")),
           let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let mode = meta["dolt_mode"] as? String, mode != "embedded" {
            return .server
        }
        if has("dolt") { return .server }
        let files = (try? fm.contentsOfDirectory(atPath: beads.path)) ?? []
        if files.contains(where: { $0.hasSuffix(".db") || $0 == "issues.jsonl" }) { return .legacy }
        return nil
    }
}

/// A granted folder as the app remembers it: the bookmark's key and the path it had.
public struct GrantedFolder: Identifiable, Hashable, Sendable, Codable {
    public var id: String { key }
    public let key: String
    public var path: String
    /// Projects (their .beads relative paths) the person unticked: never opened.
    public var excluded: [String]

    public init(key: String, path: String, excluded: [String] = []) {
        self.key = key
        self.path = path
        self.excluded = excluded
    }


    /// The projects under this folder the person chose to see.
    public func included(_ found: [FoundProject]) -> [FoundProject] {
        found.filter { !excluded.contains($0.relativePath) }
    }

    public enum Health: Hashable, Sendable {
        case ok
        /// The folder was moved or renamed; the bookmark followed it.
        case moved(to: String)
        /// The bookmark no longer resolves (deleted, on a disconnected disk, access revoked).
        case missing
    }

    /// Compares what the bookmark resolves to now with the path it was saved at.
    public func health(resolvedPath: String?) -> Health {
        guard let resolvedPath else { return .missing }
        guard FileManager.default.fileExists(atPath: resolvedPath) else { return .missing }
        return resolvedPath == path ? .ok : .moved(to: resolvedPath)
    }
}
