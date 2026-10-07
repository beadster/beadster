// "What holds what up?" One workflow as a map: the root on top, each step below what it waits
// on (BeadsKit DependencyMap). Canvas draws the edges; the cards are plain views.
import BeadsKit
import SwiftUI

struct MapView: View {
    let row: AppModel.FlowRow
    let back: () -> Void

    var body: some View {
        let map = DependencyMap(root: row.workflow.root, steps: row.workflow.steps)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: back) { Label("Workflows", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("\(row.workflow.root.title) · \(row.project)").foregroundStyle(.secondary)
                Spacer()
            }
            .padding([.horizontal, .top], 16)
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    Canvas { ctx, sz in
                        for edge in map.edges {
                            guard let a = point(edge.from, map, sz), let b = point(edge.to, map, sz) else { continue }
                            var path = Path()
                            path.move(to: CGPoint(x: a.x, y: a.y + 18))
                            path.addCurve(to: CGPoint(x: b.x, y: b.y - 18),
                                          control1: CGPoint(x: a.x, y: (a.y + b.y) / 2),
                                          control2: CGPoint(x: b.x, y: (a.y + b.y) / 2))
                            ctx.stroke(path, with: .color(.secondary.opacity(0.6)), lineWidth: 1.5)
                        }
                    }
                    ForEach(map.nodes) { node in
                        NodeCard(node: node)
                            .position(point(node.id, map, size) ?? .zero)
                    }
                }
            }
            .padding(24)
        }
    }

    private func point(_ id: String, _ map: DependencyMap, _ size: CGSize) -> CGPoint? {
        guard let n = map.nodes.first(where: { $0.id == id }) else { return nil }
        let rows = max(map.layers, 1)
        let cols = max(map.width(of: n.layer), 1)
        let y = size.height * (CGFloat(n.layer) + 0.5) / CGFloat(rows)
        let x = size.width * (CGFloat(n.column) + 0.5) / CGFloat(cols)
        return CGPoint(x: x, y: y)
    }
}

struct NodeCard: View {
    let node: DependencyMap.Node

    var body: some View {
        let gate = node.type == .gate && node.status != .closed
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(node.title).lineLimit(1)
            } icon: {
                if gate { Image(systemName: "hand.raised.fill").foregroundStyle(.orange) } else { StatusSymbol(status: node.status) }
            }
            Text("\(node.id) · \(node.status.rawValue.replacingOccurrences(of: "_", with: " "))")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: 220, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
