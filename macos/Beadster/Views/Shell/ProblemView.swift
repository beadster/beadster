// What a place shows instead of beads: a project that can't open, a folder that is gone, a
// project with no beads yet. One calm title, one line, one button (HIG: empty states say what
// happened and what to do). The words are BeadsKit's Problem.
import BeadsKit
import SwiftUI

struct ProblemView: View {
    let problem: Problem
    let perform: (Problem.Action) -> Void
    @State private var confirmingUpgrade = false

    var body: some View {
        ContentUnavailableView {
            Label(problem.title, systemImage: problem.symbol)
        } description: {
            Text(problem.message)
            if let detail = problem.detail, !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } actions: {
            if let action = problem.action {
                Button(action.title) {
                    if action == .upgradeProject { confirmingUpgrade = true } else { perform(action) }
                }
                .controlSize(.large)
            }
        }
        .confirmationDialog("Update this project to beads \(BeadsVersion.carried)?", isPresented: $confirmingUpgrade) {
            Button("Update Project") { perform(.upgradeProject) }
        } message: {
            Text("A bd older than \(BeadsVersion.carried) can't open it afterwards.")
        }
    }
}
