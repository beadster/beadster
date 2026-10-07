// "What changed since I last looked?" beads' audit log across every project, newest first,
// grouped by day. Live: an agent's write shows up on top within a second.
import BeadsKit
import SwiftUI

struct ActivityView: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.activity.isEmpty {
            // U15 draws this empty state
            ContentUnavailableView("No Changes This Week", systemImage: "clock.arrow.circlepath",
                                   description: Text("Every change an agent or you make to a bead shows up here."))
        } else {
            List {
                ForEach(days, id: \.0) { day, items in
                    Section(day) {
                        ForEach(items) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(item.event.at, format: .dateTime.hour().minute())
                                    .monospacedDigit().foregroundStyle(.secondary).fixedSize().frame(minWidth: 64, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.summary).fontWeight(.medium)
                                    Text(detail(item)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    /// The bead and its project, or only the project for a run of many beads.
    private func detail(_ item: ActivityItem) -> String {
        if item.count > 1 { return item.project }
        return [item.title, "\(item.project) · \(item.event.beadID)"].compactMap { $0 }.joined(separator: " · ")
    }

    /// Today, Yesterday, then the date.
    private var days: [(String, [ActivityItem])] {
        let cal = Calendar.current
        var order: [String] = []
        var groups: [String: [ActivityItem]] = [:]
        for item in model.activity {
            let d = item.event.at
            let key = cal.isDateInToday(d) ? "Today" : cal.isDateInYesterday(d) ? "Yesterday"
                : d.formatted(.dateTime.weekday(.wide).month().day())
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}
