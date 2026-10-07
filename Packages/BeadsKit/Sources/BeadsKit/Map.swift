import Foundation

/// A workflow drawn as layers: the root on top, each step one layer below the deepest step it
/// waits on. Pure: the view only places what this computes.
public struct DependencyMap: Sendable {
    public struct Node: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let status: BeadStatus
        public let type: BeadType
        public let awaitType: String?
        public let layer: Int
        public let column: Int
    }

    public struct Edge: Hashable, Sendable {
        public let from: String
        public let to: String
    }

    public let nodes: [Node]
    public let edges: [Edge]
    public var layers: Int { (nodes.map(\.layer).max() ?? 0) + 1 }
    public func width(of layer: Int) -> Int { nodes.filter { $0.layer == layer }.count }

    public init(root: Bead, steps: [Bead]) {
        let ids = Set(steps.map(\.id))
        // blockers of each step, inside this workflow only
        var waitsOn: [String: [String]] = [:]
        for s in steps {
            waitsOn[s.id] = s.edges.filter { $0.kind.isBlocking && ids.contains($0.dependsOnID) }.map(\.dependsOnID)
        }
        var depth: [String: Int] = [:]
        func layer(_ id: String, _ seen: Set<String>) -> Int {
            if let d = depth[id] { return d }
            let parents = (waitsOn[id] ?? []).filter { !seen.contains($0) } // a cycle never loops
            let d = 1 + (parents.map { layer($0, seen.union([id])) }.max() ?? 0)
            depth[id] = d
            return d
        }
        for s in steps { _ = layer(s.id, []) }

        var nodes = [Node(id: root.id, title: root.title, status: root.status, type: root.type,
                          awaitType: root.awaitType, layer: 0, column: 0)]
        var columns: [Int: Int] = [:]
        for s in steps {
            let l = depth[s.id] ?? 1
            let c = columns[l, default: 0]
            columns[l] = c + 1
            nodes.append(Node(id: s.id, title: s.title, status: s.status, type: s.type, awaitType: s.awaitType, layer: l, column: c))
        }
        var edges: [Edge] = []
        for s in steps {
            let blockers = waitsOn[s.id] ?? []
            if blockers.isEmpty { edges.append(Edge(from: root.id, to: s.id)) }
            edges += blockers.map { Edge(from: $0, to: s.id) }
        }
        self.nodes = nodes
        self.edges = edges
    }
}
