// Notifications for what changed while the person looked elsewhere: a gate waiting (with
// Approve and Reject on the banner), an agent gone quiet, a bead assigned to them, and (off
// by default) a bead closed. What counts as new is NoticeState's job; this only posts.
import BeadsKit
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let gateCategory = "gate"
    static let approve = "approve"
    static let reject = "reject"

    private var state = NoticeState()
    private var asked = false
    /// Called for a banner's Approve or Reject, and for a click (opens the place).
    var onAction: ((_ notice: (kind: String, projectID: String, beadID: String), _ action: String) async -> Void)?

    override init() {
        super.init()
        guard ShotMode.scene == nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.gateCategory, actions: [
                UNNotificationAction(identifier: Self.approve, title: "Approve"),
                UNNotificationAction(identifier: Self.reject, title: "Reject", options: .destructive),
            ], intentIdentifiers: []),
        ])
    }

    func update(needsYou: ProjectLibrary.NeedsYou, working: [AppModel.WorkRow], closed: [ActivityItem]) async {
        let notices = state.update(needsYou: needsYou,
                                   working: working.map { ($0.projectID, $0.project, $0.bead) },
                                   closedEvents: closed, now: Date())
        guard ShotMode.scene == nil else { return }
        let allowed = notices.filter { Self.allowed($0.kind) }
        guard !allowed.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        if !asked {
            asked = true
            // asked the first time there is something to say, never at launch (HIG)
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        for notice in allowed {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.threadIdentifier = notice.projectID
            content.userInfo = ["kind": notice.kind.rawValue, "projectID": notice.projectID, "beadID": notice.beadID]
            if notice.kind == .gate { content.categoryIdentifier = Self.gateCategory }
            if notice.kind == .gate || notice.kind == .assigned { content.sound = .default }
            try? await center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: nil))
        }
    }

    /// Settings › Notifications decides; the defaults match SettingsView's.
    static func allowed(_ kind: Notice.Kind) -> Bool {
        let d = UserDefaults.standard
        func on(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) == nil ? fallback : d.bool(forKey: key) }
        switch kind {
        case .gate: return on("notify.gates", true)
        case .quiet: return on("notify.quiet", true)
        case .assigned: return on("notify.assigned", true)
        case .closed: return on("notify.closed", false)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let kind = info["kind"] as? String, let projectID = info["projectID"] as? String,
              let beadID = info["beadID"] as? String else { return }
        let action = response.actionIdentifier
        await MainActor.run { [weak self] in
            guard let handler = self?.onAction else { return }
            Task { await handler((kind, projectID, beadID), action) }
        }
    }
}
