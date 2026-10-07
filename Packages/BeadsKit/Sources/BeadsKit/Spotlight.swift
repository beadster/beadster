import Foundation

/// One bead as Spotlight shows it: found by title, id, project and labels; its id says which
/// project and bead to open. CoreSpotlight glue lives in the app; this is what it indexes.
public struct SpotlightItem: Hashable, Sendable {
    public let uniqueID: String
    /// The project: a whole project's items are replaced or removed together.
    public let domain: String
    public let title: String
    public let detail: String
    public let keywords: [String]
    public let text: String?
    public let modified: Date

    /// Open beads only: closed work is history, not something to jump to.
    public static func items(projectID: String, project: String, beads: [Bead]) -> [SpotlightItem] {
        beads.filter { $0.status != .closed }.map { bead in
            SpotlightItem(uniqueID: "\(projectID)|\(bead.id)", domain: projectID, title: bead.title,
                          detail: "\(bead.id) · \(project)", keywords: [bead.id, project] + bead.labels,
                          text: bead.description, modified: bead.updatedAt)
        }
    }

    /// The project and bead a result opens. Project ids hold slashes, bead ids never a "|".
    public static func target(of uniqueID: String) -> (projectID: String, beadID: String)? {
        guard let bar = uniqueID.lastIndex(of: "|") else { return nil }
        let project = String(uniqueID[..<bar]), bead = String(uniqueID[uniqueID.index(after: bar)...])
        return project.isEmpty || bead.isEmpty ? nil : (project, bead)
    }
}

extension ProjectLibrary {
    /// Every open bead of one project, for Spotlight.
    public func openBeads(_ id: String) async -> [Bead] {
        await loadSnapshots()
        return entries.first { $0.id == id }?.snapshot ?? []
    }
}
