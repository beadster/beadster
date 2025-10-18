# transition notifications

notifications when issues change status (especially when closed by someone else)

## current state

- macOS app has UNUserNotificationCenter working
- sync daemon pulls changes from cloud every 30s
- device_tracking exists in API but not used yet
- sync applies changes without detecting what changed

## goal

notify user when someone else closes their task

## implementation plan

### 1. device identification

generate and store unique device ID for this Mac

```swift
// in SyncDaemon
private let deviceId: String

init() {
    // get or create device ID
    if let stored = UserDefaults.standard.string(forKey: "beadster_device_id") {
        deviceId = stored
    } else {
        deviceId = UUID().uuidString.lowercased()
        UserDefaults.standard.set(deviceId, forKey: "beadster_device_id")
    }
}
```

### 2. track state before sync

before pulling changes, snapshot current issue states

```swift
private func pullAndApplyChanges(project: ProjectInfo, projectURL: URL, sourceId: String) async throws {
    let db = BeadsDatabase(beadsDir: projectURL)
    try db.open()
    defer { db.close() }

    // snapshot current state
    let beforeState = try db.getAllIssues()
    let beforeMap = Dictionary(uniqueKeysAndValues: beforeState.map { ($0.id, $0) })

    // pull changes from cloud
    let changes = try await APIClient.shared.pullChanges(sourceId: sourceId, since: since)

    // detect transitions before applying
    let transitions = detectTransitions(before: beforeMap, changes: changes)

    // apply changes
    for issue in changes {
        try await applyChange(issue: issue, projectPath: projectURL.path)
    }

    // notify about remote transitions
    await notifyTransitions(transitions, sourceId: sourceId)
}
```

### 3. detect status transitions

```swift
struct IssueTransition {
    let issueId: String
    let title: String
    let fromStatus: String
    let toStatus: String
}

private func detectTransitions(
    before: [String: Issue],
    changes: [Issue]
) -> [IssueTransition] {
    var transitions: [IssueTransition] = []

    for change in changes {
        guard let oldIssue = before[change.id] else { continue }

        // detect status change
        if oldIssue.status != change.status {
            transitions.append(IssueTransition(
                issueId: change.id,
                title: change.title,
                fromStatus: oldIssue.status,
                toStatus: change.status
            ))
        }
    }

    return transitions
}
```

### 4. check who made the change

use device_tracking from API to see if change was made by us or someone else

```swift
private func notifyTransitions(_ transitions: [IssueTransition], sourceId: String) async {
    for transition in transitions {
        // only notify for transitions to closed
        guard transition.toStatus == "closed" else { continue }

        // check who made this change
        let wasUs = try? await wasChangeMadeByUs(issueId: transition.issueId, sourceId: sourceId)

        // only notify if someone else closed it
        if wasUs == false {
            sendNotification(
                title: "Issue Closed",
                body: transition.title
            )
        }
    }
}

private func wasChangeMadeByUs(issueId: String, sourceId: String) async throws -> Bool {
    // call API to get device_tracking for this issue
    let tracking = try await APIClient.shared.getDeviceTracking(sourceId: sourceId, issueId: issueId)

    // check if last device_id matches ours
    return tracking.lastDeviceId == deviceId
}
```

### 5. add API endpoint for device tracking

need new endpoint in API:

```typescript
// GET /sources/:sourceId/issues/:issueId/tracking
app.get('/sources/:sourceId/issues/:issueId/tracking', async (c) => {
  const { sourceId, issueId } = c.req.param()

  const result = await c.env.DB.prepare(`
    SELECT device_id, updated_at
    FROM device_tracking
    WHERE source_id = ? AND issue_id = ?
    ORDER BY updated_at DESC
    LIMIT 1
  `).bind(sourceId, issueId).first()

  return c.json({
    lastDeviceId: result?.device_id,
    lastUpdated: result?.updated_at
  })
})
```

alternatively: include device_id in pullChanges response

```typescript
// in /sources/:sourceId/issues endpoint
// add device_tracking join to get last device_id
const issues = await c.env.DB.prepare(`
  SELECT i.*, dt.device_id as last_device_id
  FROM issues i
  LEFT JOIN device_tracking dt ON i.id = dt.issue_id AND i.source_id = dt.source_id
  WHERE i.source_id = ? AND i.updated_at > ?
  ORDER BY dt.updated_at DESC
`).bind(sourceId, since).all()
```

### 6. notification preferences (optional)

add settings to control notifications:

```swift
struct NotificationPreferences {
    var notifyOnClosed: Bool = true
    var notifyOnReopened: Bool = false
    var notifyOnStatusChange: Bool = false
    var soundEnabled: Bool = true
}

// in SettingsView
Toggle("Notify when issues are closed", isOn: $preferences.notifyOnClosed)
Toggle("Notify on any status change", isOn: $preferences.notifyOnStatusChange)
Toggle("Play notification sound", isOn: $preferences.soundEnabled)
```

## alternative simpler approach

instead of checking device_tracking, use timestamps:

- if issue.updated_at is newer than last sync AND status changed to closed
- assume it was changed by someone else
- this is simpler but less accurate (could be our own change that synced)

```swift
private func notifyTransitions(_ transitions: [IssueTransition]) {
    for transition in transitions {
        guard transition.toStatus == "closed" else { continue }

        // simple heuristic: if we just synced and it changed, probably not us
        sendNotification(
            title: "Issue Closed",
            body: transition.title
        )
    }
}
```

## edge cases

- user closes issue in UI → syncs immediately → no notification (device_id matches)
- user closes issue via CLI → syncs → should we notify? (same device but different interface)
- issue closed offline → syncs later → should notify based on timestamp vs last_sync
- rapid status changes → only notify on final transition to closed

## testing

- create issue on device A
- close it on device B (or via web/CLI)
- wait for sync on device A (30s)
- verify notification appears
- verify notification doesn't appear when closing locally

## future enhancements

- show who closed it: "Issue closed by [device name]"
- allow naming devices in settings
- rich notifications with actions (view, reopen)
- notification history/log
- batch notifications: "3 issues were closed"
