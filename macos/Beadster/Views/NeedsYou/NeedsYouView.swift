// "What is waiting on me?" Gates only a person can clear, then gates waiting on something
// else (so a stuck release is visible), then open beads assigned to you.
import BeadsKit
import SwiftUI

struct NeedsYouView: View {
    @Bindable var model: AppModel

    var body: some View {
        let n = model.needsYou
        if n.approvals.isEmpty && n.waiting.isEmpty && n.assigned.isEmpty {
            // U15 draws this empty state
            ContentUnavailableView("Nothing Needs You", systemImage: "hand.raised",
                                   description: Text("Approvals and beads assigned to you show up here."))
        } else {
            List {
                if !n.approvals.isEmpty {
                    Section("Approvals") {
                        ForEach(n.approvals, id: \.gate.id) { item in
                            HStack(spacing: 12) {
                                Image(systemName: "hand.raised.fill").foregroundStyle(Color.warningInk).font(.title3)
                                    .accessibilityLabel("Approval")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.gate.title).fontWeight(.medium)
                                    Text(detail(item.project, item.gate.reason, since: item.gate.bead.createdAt))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Reject") { Task { await model.decide(gate: item.gate, in: item.projectID, approve: false) } }
                                Button("Approve") { Task { await model.decide(gate: item.gate, in: item.projectID, approve: true) } }
                                    .buttonStyle(.borderedProminent)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                if !n.waiting.isEmpty {
                    Section("Waiting on Something Else") {
                        ForEach(n.waiting, id: \.gate.id) { item in
                            HStack(spacing: 12) {
                                Image(systemName: "hourglass").foregroundStyle(.secondary).font(.title3)
                                    .accessibilityLabel("Waiting")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.gate.title)
                                    Text("\(item.project) · \(condition(item.gate.condition))").foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.gate.bead.createdAt, format: .relative(presentation: .named))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                if !n.assigned.isEmpty {
                    Section("Assigned to You") {
                        ForEach(n.assigned, id: \.bead.id) { item in
                            HStack(spacing: 12) {
                                KindSymbol(type: item.bead.type).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.bead.title)
                                    Text("\(item.project) · \(item.bead.id)").foregroundStyle(.secondary)
                                }
                                Spacer()
                                PriorityText(priority: item.bead.priority)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                if let error = model.lastError {
                    Text(error).foregroundStyle(Color.dangerInk).textSelection(.enabled)
                }
            }
        }
    }

    private func detail(_ project: String, _ reason: String?, since: Date) -> String {
        let waited = since.formatted(.relative(presentation: .named))
        return [project, reason, "asked \(waited)"].compactMap { $0 }.joined(separator: " · ")
    }

    private func condition(_ c: Gate.Condition) -> String {
        switch c {
        case .human: "your approval"
        case .timer: "a timer"
        case .pullRequest(let n): n.map { "pull request #\($0)" } ?? "a pull request"
        case .run(let n): n.map { "CI run \($0)" } ?? "a CI run"
        case .bead(let id): id.map { "bead \($0)" } ?? "another bead"
        case .other(let s): s
        }
    }
}
