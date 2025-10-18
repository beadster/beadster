# beadster macos app

native macos app for syncing and managing bd issues

## overview

native swift app that:
- runs sync daemon in background
- discovers and monitors .beads/ directories
- enriches issues with context capture
- provides minimal ui for viewing/managing tasks
- authenticates with sign in with apple

## architecture

```
beadster.app/
├── Contents/
│   ├── MacOS/
│   │   └── beadster           # main app binary
│   └── Resources/
│       └── sync-daemon        # background sync process
```

### components

**main app (swiftui)**
- menubar icon (lives in menubar)
- settings window
- task list window
- project discovery
- authentication

**sync daemon (swift)**
- background process (launchd)
- monitors .beads/ directories
- syncs with beadster api
- context capture with claude
- file system watching

## authentication

### sign in with apple

```swift
import AuthenticationServices

class AuthManager: ObservableObject {
  @Published var user: User?
  @Published var isAuthenticated = false

  func signInWithApple() {
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = [.email, .fullName]

    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.performRequests()
  }

  func handleAppleIDCredential(_ credential: ASAuthorizationAppleIDCredential) {
    // send to beadster api
    let appleToken = credential.identityToken
    Task {
      let response = await api.post("/auth/apple", body: {
        "apple_token": appleToken,
        "user_id": credential.user
      })

      self.user = response.user
      self.isAuthenticated = true

      // store auth token
      Keychain.set(response.auth_token, forKey: "beadster_auth_token")
    }
  }
}
```

### device registration

```swift
func registerDevice() async throws {
  let deviceId = await DeviceInfo.hardwareUUID()
  let deviceName = Host.current().localizedName

  await api.post("/devices/register", body: {
    "device_id": deviceId,
    "device_name": deviceName,
    "device_type": "mac",
    "platform": "macos",
    "platform_version": ProcessInfo.processInfo.operatingSystemVersionString
  })
}
```

## project discovery

### sandbox-safe folder selection

app is sandboxed for app store, so we need security bookmarks:

```swift
class ProjectDiscovery: ObservableObject {
  @Published var projects: [Project] = []
  @Published var scanRoots: [URL] = []

  func addScanRoot() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Select a folder to scan for projects"

    if panel.runModal() == .OK, let url = panel.url {
      // create security bookmark for sandbox access
      guard let bookmark = try? url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      ) else {
        print("failed to create bookmark")
        return
      }

      // save bookmark
      UserDefaults.standard.set(bookmark, forKey: "scan_root_\(url.path)")
      scanRoots.append(url)

      // scan this root
      Task {
        await scanForProjects(in: url)
      }
    }
  }

  func loadSavedScanRoots() {
    let defaults = UserDefaults.standard
    let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("scan_root_") }

    for key in keys {
      guard let bookmark = defaults.data(forKey: key) else { continue }

      var isStale = false
      guard let url = try? URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ) else { continue }

      if isStale {
        // refresh bookmark
        if let newBookmark = try? url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        ) {
          defaults.set(newBookmark, forKey: key)
        }
      }

      scanRoots.append(url)
    }
  }

  func scanForProjects(in rootUrl: URL) async {
    // start accessing security scoped resource
    guard rootUrl.startAccessingSecurityScopedResource() else {
      print("failed to access \(rootUrl)")
      return
    }
    defer { rootUrl.stopAccessingSecurityScopedResource() }

    let enumerator = FileManager.default.enumerator(
      at: rootUrl,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    while let url = enumerator?.nextObject() as? URL {
      // check if .beads/ exists
      let beadsDir = url.appendingPathComponent(".beads")
      if FileManager.default.fileExists(atPath: beadsDir.path) {
        await addProject(url)
      }
    }
  }

  func addProject(_ path: URL) async {
    // create bookmark for this project
    guard let bookmark = try? path.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) else {
      print("failed to create project bookmark")
      return
    }

    let project = Project(
      path: path.path,
      name: path.lastPathComponent,
      type: detectProjectType(path),
      bookmark: bookmark
    )

    projects.append(project)

    // save project bookmarks
    saveProjects()

    // register with sync daemon
    await SyncDaemon.shared.addSource(project)
  }

  func detectProjectType(_ path: URL) -> String {
    if FileManager.default.fileExists(atPath: path.appendingPathComponent(".git").path) {
      return "local-git"
    }
    return "local-no-git"
  }
}
```

### manual project addition

```swift
struct AddProjectView: View {
  @State private var selectedPath: URL?

  var body: some View {
    VStack {
      Button("Select Project Folder") {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
          selectedPath = panel.url
        }
      }

      if let path = selectedPath {
        Text("Selected: \(path.path)")

        Button("Add Project") {
          Task {
            await projectDiscovery.addProject(path)
          }
        }
      }
    }
  }
}
```

## sync daemon

### background service

```swift
class SyncDaemon {
  static let shared = SyncDaemon()

  private var sources: [Source] = []
  private var watchers: [FileSystemWatcher] = []
  private var syncTimer: Timer?

  func start() {
    // load sources from disk
    sources = loadSources()

    // start file watchers
    for source in sources {
      let watcher = FileSystemWatcher(path: source.path)
      watcher.onChange = { [weak self] in
        self?.syncSource(source)
      }
      watchers.append(watcher)
    }

    // periodic sync every 5 minutes
    syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
      Task {
        await self.syncAll()
      }
    }
  }

  func syncSource(_ source: Source) async {
    let beadsPath = "\(source.path)/.beads"
    let issuesFile = "\(beadsPath)/issues.jsonl"

    // read local issues
    let localIssues = try? parseJSONL(issuesFile)

    // fetch from cloud
    let cloudIssues = await api.get("/sources/\(source.id)/issues")

    // merge changes
    let merged = mergeIssues(local: localIssues, cloud: cloudIssues)

    // write back to local
    try? writeJSONL(merged.local, to: issuesFile)

    // push to cloud
    await api.post("/sources/\(source.id)/sync", body: merged.cloud)

    // update last sync time
    source.last_sync = Date()
    saveSources()
  }

  func syncAll() async {
    for source in sources {
      await syncSource(source)
    }
  }
}
```

### file system watching

```swift
import Dispatch

class FileSystemWatcher {
  private let path: String
  private var source: DispatchSourceFileSystemObject?
  var onChange: (() -> Void)?

  init(path: String) {
    self.path = path
    startWatching()
  }

  func startWatching() {
    let fd = open(path.cString(using: .utf8), O_EVTONLY)
    guard fd >= 0 else { return }

    source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: .write,
      queue: DispatchQueue.global()
    )

    source?.setEventHandler { [weak self] in
      self?.onChange?()
    }

    source?.setCancelHandler {
      close(fd)
    }

    source?.resume()
  }

  deinit {
    source?.cancel()
  }
}
```

## context capture

### integration with claude code

requires permission to access ~/.claude folder:

```swift
class ContextCapture {
  @Published var claudeFolderAccess: URL?

  func requestClaudeFolderAccess() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Select .claude folder for context capture"
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude")

    if panel.runModal() == .OK, let url = panel.url {
      // create security bookmark
      guard let bookmark = try? url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      ) else {
        print("failed to create claude folder bookmark")
        return
      }

      // save bookmark
      UserDefaults.standard.set(bookmark, forKey: "claude_folder_bookmark")
      claudeFolderAccess = url
    }
  }

  func loadClaudeFolderAccess() {
    guard let bookmark = UserDefaults.standard.data(forKey: "claude_folder_bookmark") else {
      return
    }

    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: bookmark,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) else { return }

    if isStale {
      // refresh bookmark
      if let newBookmark = try? url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      ) {
        UserDefaults.standard.set(newBookmark, forKey: "claude_folder_bookmark")
      }
    }

    claudeFolderAccess = url
  }

  func enrichIssue(_ issue: Issue) async throws {
    guard let sessionId = issue.session_id else { return }
    guard let claudeFolder = claudeFolderAccess else {
      print("no access to .claude folder - request permission first")
      return
    }

    // access security scoped resource
    guard claudeFolder.startAccessingSecurityScopedResource() else {
      print("failed to access claude folder")
      return
    }
    defer { claudeFolder.stopAccessingSecurityScopedResource() }

    // extract conversation context
    let context = try await extractContext(sessionId: sessionId, createdAt: issue.created_at)

    // get auth token
    guard let token = try? getClaudeCodeToken(from: claudeFolder) else {
      print("no claude code token - skipping enrichment")
      return
    }

    // call claude haiku
    let enriched = try await callHaiku(token: token, context: context, issue: issue)

    // update issue
    issue.body = enriched.summary
    issue.design = enriched.implementation_notes
    issue.acceptance_criteria = enriched.acceptance_criteria
    issue.notes = enriched.rationale
    issue.context_captured = true

    // save to local .beads/
    try saveIssue(issue)
  }

  func getClaudeCodeToken(from claudeFolder: URL) throws -> String {
    // read from .credentials.json
    let credsFile = claudeFolder.appendingPathComponent(".credentials.json")
    let data = try Data(contentsOf: credsFile)
    let creds = try JSONDecoder().decode(ClaudeCredentials.self, from: data)

    // check expiration
    if Date().timeIntervalSince1970 * 1000 >= creds.claudeAiOauth.expiresAt {
      throw AuthError.tokenExpired
    }

    return creds.claudeAiOauth.accessToken
  }

  func callHaiku(token: String, context: ConversationContext, issue: Issue) async throws -> EnrichedContext {
    let prompt = """
    analyze this conversation where an issue was created:

    conversation before:
    \(context.before.map { $0.content }.joined(separator: "\n\n"))

    issue created:
    title: \(issue.title)
    body: \(issue.body ?? "no description")

    conversation after:
    \(context.after.map { $0.content }.joined(separator: "\n\n"))

    extract:
    1. detailed summary (what problem is being solved)
    2. why this issue was created (rationale)
    3. mentioned files/code (relevant context)
    4. implementation notes (any technical details discussed)
    5. acceptance criteria (what would make this complete)

    return as json.
    """

    let response = try await anthropicAPI.messages.create(
      apiKey: token,
      model: "claude-3-haiku-20240307",
      maxTokens: 1024,
      messages: [.init(role: "user", content: prompt)]
    )

    return try JSONDecoder().decode(EnrichedContext.self, from: response.content[0].text.data(using: .utf8)!)
  }
}
```

## ui

### main window app

standard macos window (not menubar):

```swift
@main
struct BeadsterApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      MainView()
        .frame(minWidth: 800, minHeight: 600)
    }

    Settings {
      SettingsView()
    }
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // start sync daemon
    SyncDaemon.shared.start()
  }
}
```

### task list view

```swift
struct TaskListView: View {
  @StateObject private var taskStore = TaskStore()
  @State private var filter: TaskFilter = .all

  var body: some View {
    VStack(spacing: 0) {
      // header
      HStack {
        Text("Tasks")
          .font(.headline)

        Spacer()

        Picker("", selection: $filter) {
          Text("All").tag(TaskFilter.all)
          Text("Open").tag(TaskFilter.open)
          Text("Mine").tag(TaskFilter.mine)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
      }
      .padding()

      Divider()

      // task list
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(taskStore.filteredTasks(filter)) { task in
            TaskRow(task: task)
          }
        }
        .padding()
      }

      Divider()

      // footer
      HStack {
        Button(action: { taskStore.refresh() }) {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)

        Spacer()

        Text("\(taskStore.tasks.count) tasks")
          .font(.caption)
          .foregroundColor(.secondary)

        Button(action: { openMainWindow() }) {
          Image(systemName: "arrow.up.right.square")
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
    .frame(width: 400, height: 500)
  }
}
```

### task row

```swift
struct TaskRow: View {
  let task: Issue
  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 12) {
      // checkbox
      Button(action: { toggleComplete() }) {
        Image(systemName: task.status == "closed" ? "checkmark.circle.fill" : "circle")
          .foregroundColor(task.status == "closed" ? .green : .gray)
      }
      .buttonStyle(.plain)

      // content
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(task.beads_id ?? task.id)
            .font(.caption)
            .foregroundColor(.secondary)

          if let priority = task.priority {
            PriorityBadge(priority: priority)
          }
        }

        Text(task.title)
          .font(.body)
          .strikethrough(task.status == "closed")

        if let dueAt = task.due_at {
          DueDateLabel(dueAt: dueAt)
        }
      }

      Spacer()

      // actions (show on hover)
      if isHovered {
        Button(action: { openInBrowser() }) {
          Image(systemName: "arrow.up.right")
        }
        .buttonStyle(.plain)
      }
    }
    .padding(8)
    .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
    .cornerRadius(6)
    .onHover { hovering in
      isHovered = hovering
    }
  }

  func toggleComplete() {
    Task {
      await taskStore.updateStatus(task, status: task.status == "closed" ? "open" : "closed")
    }
  }

  func openInBrowser() {
    if let url = URL(string: "https://beadster.com/issues/\(task.id)") {
      NSWorkspace.shared.open(url)
    }
  }
}
```

### priority badge

```swift
struct PriorityBadge: View {
  let priority: Int

  var body: some View {
    Text("P\(priority)")
      .font(.caption2)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(priorityColor.opacity(0.2))
      .foregroundColor(priorityColor)
      .cornerRadius(4)
  }

  var priorityColor: Color {
    switch priority {
    case 0: return .red
    case 1: return .orange
    case 2: return .yellow
    case 3: return .blue
    default: return .gray
    }
  }
}
```

### due date label

```swift
struct DueDateLabel: View {
  let dueAt: Int

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "clock")
      Text(formattedDueDate)
    }
    .font(.caption)
    .foregroundColor(isOverdue ? .red : .secondary)
  }

  var dueDate: Date {
    Date(timeIntervalSince1970: TimeInterval(dueAt))
  }

  var isOverdue: Bool {
    dueDate < Date()
  }

  var formattedDueDate: String {
    if isOverdue {
      return "overdue"
    }

    let hours = dueDate.timeIntervalSinceNow / 3600
    if hours < 24 {
      return "due in \(Int(hours))h"
    }

    let days = Int(hours / 24)
    return "due in \(days)d"
  }
}
```

## settings window

```swift
struct SettingsView: View {
  var body: some View {
    TabView {
      GeneralSettings()
        .tabItem {
          Label("General", systemImage: "gear")
        }

      ProjectsSettings()
        .tabItem {
          Label("Projects", systemImage: "folder")
        }

      SyncSettings()
        .tabItem {
          Label("Sync", systemImage: "arrow.triangle.2.circlepath")
        }
    }
    .frame(width: 500, height: 400)
  }
}
```

### general settings

```swift
struct GeneralSettings: View {
  @AppStorage("launch_at_login") private var launchAtLogin = true
  @AppStorage("show_notifications") private var showNotifications = true
  @AppStorage("context_capture") private var contextCapture = true

  var body: some View {
    Form {
      Section {
        Toggle("Launch at login", isOn: $launchAtLogin)
        Toggle("Show notifications", isOn: $showNotifications)
        Toggle("Auto-capture context", isOn: $contextCapture)
      }

      Section {
        HStack {
          Text("Account")
          Spacer()
          if let user = authManager.user {
            Text(user.email)
              .foregroundColor(.secondary)
          }
          Button("Sign Out") {
            authManager.signOut()
          }
        }
      }
    }
    .padding()
  }
}
```

### projects settings

```swift
struct ProjectsSettings: View {
  @StateObject private var projectDiscovery = ProjectDiscovery()
  @State private var isScanning = false

  var body: some View {
    VStack {
      HStack {
        Text("Monitored Projects")
          .font(.headline)

        Spacer()

        Button("Scan for Projects") {
          Task {
            isScanning = true
            await projectDiscovery.scanForProjects()
            isScanning = false
          }
        }
        .disabled(isScanning)

        Button("Add Manually") {
          // show file picker
        }
      }
      .padding()

      List(projectDiscovery.projects) { project in
        ProjectRow(project: project)
      }
    }
  }
}

struct ProjectRow: View {
  let project: Project

  var body: some View {
    HStack {
      Image(systemName: project.type == "local-git" ? "arrow.triangle.branch" : "folder")
        .foregroundColor(.secondary)

      VStack(alignment: .leading) {
        Text(project.name)
          .font(.body)
        Text(project.path)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      if let lastSync = project.last_sync {
        Text("synced \(lastSync.timeAgoString())")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Button(action: { removeProject() }) {
        Image(systemName: "minus.circle")
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, 4)
  }

  func removeProject() {
    projectDiscovery.projects.removeAll { $0.id == project.id }
    SyncDaemon.shared.removeSource(project.id)
  }
}
```

### sync settings

```swift
struct SyncSettings: View {
  @AppStorage("sync_interval") private var syncInterval = 300 // seconds
  @AppStorage("context_window_size") private var contextWindowSize = 10

  var body: some View {
    Form {
      Section("Sync") {
        Picker("Sync interval", selection: $syncInterval) {
          Text("1 minute").tag(60)
          Text("5 minutes").tag(300)
          Text("15 minutes").tag(900)
          Text("30 minutes").tag(1800)
        }

        Button("Sync Now") {
          Task {
            await SyncDaemon.shared.syncAll()
          }
        }
      }

      Section("Context Capture") {
        Stepper("Context window: \(contextWindowSize) messages", value: $contextWindowSize, in: 5...50)

        HStack {
          Text("Authentication")
          Spacer()
          if hasClaudeCodeToken() {
            Text("Claude Code")
              .foregroundColor(.green)
          } else {
            Text("Not configured")
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .padding()
  }
}
```

## notifications

```swift
import UserNotifications

class NotificationManager {
  static let shared = NotificationManager()

  func requestPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      print("notification permission: \(granted)")
    }
  }

  func notifyNewIssue(_ issue: Issue) {
    let content = UNMutableNotificationContent()
    content.title = "New Issue"
    content.body = issue.title
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: issue.id,
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request)
  }

  func notifyDueSoon(_ issue: Issue) {
    guard let dueAt = issue.due_at else { return }

    let content = UNMutableNotificationContent()
    content.title = "Task Due Soon"
    content.body = "\(issue.title) is due in 1 hour"
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: TimeInterval(dueAt - 3600 - Int(Date().timeIntervalSince1970)),
      repeats: false
    )

    let request = UNNotificationRequest(
      identifier: "\(issue.id)-due",
      content: content,
      trigger: trigger
    )

    UNUserNotificationCenter.current().add(request)
  }
}
```

## distribution

### app store

distributed via mac app store:

**entitlements:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- app sandbox -->
  <key>com.apple.security.app-sandbox</key>
  <true/>

  <!-- network access for sync -->
  <key>com.apple.security.network.client</key>
  <true/>

  <!-- user selected files (for project discovery) -->
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>

  <!-- security scoped bookmarks -->
  <key>com.apple.security.files.bookmarks.app-scope</key>
  <true/>
</dict>
</plist>
```

**app store connect:**

1. create app in app store connect
2. configure app info, pricing, screenshots
3. archive and upload via xcode
4. submit for review

**sandbox requirements:**

- use security bookmarks for all file access
- request user permission via NSOpenPanel
- no hardcoded paths outside app container
- all network calls must go through URLSession

## features summary

- ✅ sign in with apple authentication
- ✅ background sync daemon
- ✅ sandbox-safe project discovery with security bookmarks
- ✅ manual project addition via NSOpenPanel
- ✅ file system watching
- ✅ context capture with claude haiku
- ✅ ~/.claude folder access via NSOpenPanel
- ✅ main window ui (not menubar)
- ✅ mark tasks complete
- ✅ priority badges
- ✅ due date indicators
- ✅ settings window
- ✅ sync controls
- ✅ notifications
- ✅ launch at login

## tech stack

- **language**: swift 6
- **ui framework**: swiftui
- **networking**: urlsession + async/await
- **storage**: security bookmarks + userdefaults
- **auth**: authenticationservices (sign in with apple)
- **file watching**: dispatchsource
- **notifications**: usernotifications
- **distribution**: mac app store (sandboxed)
- **entitlements**: app-sandbox, network.client, user-selected files
