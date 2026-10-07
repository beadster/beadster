// "What are my agents doing right now, and is any of them stuck?" Work in progress across
// every project, with the claim each agent holds and when it was last heard from.
import BeadsKit
import SwiftUI

struct AgentsView: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.working.isEmpty {
            // U15 draws this empty state
            ContentUnavailableView("No One Is Working", systemImage: "person.2.wave.2",
                                   description: Text("When an agent claims a bead, it shows up here."))
        } else {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Table(model.working, selection: Binding(get: { model.selectedWork },
                                                        set: { id in Task { await model.inspectWork(id) } })) {
                    TableColumn("Agent") { r in HolderLabel(bead: r.bead, now: context.date) }.width(min: 120, ideal: 150)
                    TableColumn("Working On") { r in Text(r.bead.title) }.width(min: 200, ideal: 360)
                    TableColumn("Project") { r in Text(r.project) }.width(min: 70, ideal: 100, max: 160)
                    TableColumn("Claimed") { r in
                        Text(r.bead.startedAt ?? r.bead.updatedAt, format: .relative(presentation: .named)).monospacedDigit()
                    }.width(min: 80, ideal: 110, max: 140)
                    TableColumn("Last Heard") { r in
                        if let beat = r.bead.lease?.heartbeatAt {
                            Text(beat, format: .relative(presentation: .named)).monospacedDigit()
                                .foregroundStyle(r.bead.lease?.health(at: context.date) == .active ? Color.primary : Color.warningInk)
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }.width(min: 80, ideal: 110, max: 140)
                }
            }
        }
    }
}

/// Who holds the bead and how that claim is doing: a symbol and the name, the health in words
/// for VoiceOver (never colour alone).
struct HolderLabel: View {
    let bead: Bead
    let now: Date

    var body: some View {
        let health = bead.lease?.health(at: now)
        Label(bead.assignee ?? "Someone", systemImage: symbol(health))
            .foregroundStyle(health == .active || health == nil ? Color.primary : Color.warningInk)
            .accessibilityLabel("\(bead.assignee ?? "Someone"), \(word(health))")
    }

    private func symbol(_ h: Lease.Health?) -> String {
        switch h {
        case .active: "circle.fill"
        case .quiet: "exclamationmark.triangle.fill"
        case .expired: "clock.badge.xmark"
        case nil: "person.fill"
        }
    }

    private func word(_ h: Lease.Health?) -> String {
        switch h {
        case .active: "working"
        case .quiet: "gone quiet"
        case .expired: "claim ran out"
        case nil: "working, no claim timer"
        }
    }
}

struct LeaseInspector: View {
    @Bindable var model: AppModel

    var body: some View {
        if let row = model.working.first(where: { $0.id == model.selectedWork }) {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let lease = row.bead.lease
                let health = lease?.health(at: context.date)
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(headline(row.bead, health), systemImage: health == .active || health == nil ? "circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(health == .active || health == nil ? Color.primary : Color.warningInk)
                                .font(.headline)
                            if let lease, health != .active {
                                Text(explain(lease, health, now: context.date))
                            }
                        }
                    }
                    Section("Claim") {
                        LabeledContent("Bead", value: "\(row.bead.id)  \(row.bead.title)")
                        LabeledContent("Project", value: row.project)
                        LabeledContent("Claimed") { Text(row.bead.startedAt ?? row.bead.updatedAt, format: .relative(presentation: .named)) }
                        if let beat = lease?.heartbeatAt {
                            LabeledContent("Last heartbeat") { Text(beat, format: .relative(presentation: .named)) }
                        }
                        if let lease {
                            LabeledContent(lease.isExpired(at: context.date) ? "Ran out" : "Ends") {
                                Text(lease.expiresAt, format: .relative(presentation: .named))
                            }
                        }
                    }
                    if !model.workHistory.isEmpty {
                        Section("Last Changes") {
                            ForEach(model.workHistory.prefix(5)) { e in
                                LabeledContent(e.summary) { Text(e.at, format: .relative(presentation: .named)).monospacedDigit() }
                            }
                        }
                    }
                    Section {
                        Button("Release Now") { Task { await model.release(row) } }
                        if let error = model.lastError {
                            Text(error).foregroundStyle(Color.dangerInk).textSelection(.enabled)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right",
                                   description: Text("Select an agent to see its claim."))
        }
    }

    private func headline(_ bead: Bead, _ h: Lease.Health?) -> String {
        let who = bead.assignee ?? "Someone"
        switch h {
        case .quiet: return "\(who) has gone quiet"
        case .expired: return "\(who)'s claim ran out"
        case .active, nil: return "\(who) is working on it"
        }
    }

    private func explain(_ lease: Lease, _ h: Lease.Health?, now: Date) -> String {
        let ends = lease.expiresAt.formatted(.relative(presentation: .named))
        switch h {
        case .quiet: return "No heartbeat for a while. The claim ends \(ends) and the bead goes back to Ready."
        case .expired: return "The claim ended \(ends). The bead goes back to Ready when beads next checks claims, or now with Release Now."
        default: return ""
        }
    }
}
