// P4: proves beads runs inside the App Store sandbox through a folder bookmark.
// Same entitlements as Beadster, its own bundle id, so its container and bookmarks are its own.
//
// Run 1: Choose Folder… (a fixture project's folder, e.g. ~/.cache/beadster/fixtures/claims)
//        → bookmark saved → the cycle runs → report written.
// Run 2: relaunch → the bookmark resolves without any panel → the cycle runs again.
// The fence: a folder that was never granted must be refused, and so must ~/.config and ~/.dolt.
// Report: ~/Library/Containers/ai.beadster.sandboxprobe/Data/Documents/probe-report.json
import AppKit
import SwiftUI

@main
struct SandboxProbeApp: App {
    @State private var probe = Probe()
    var body: some Scene {
        WindowGroup("Sandbox Probe") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Choose Folder…") { probe.choose() }
                    Button("Run Again") { probe.runSaved() }.disabled(!probe.hasBookmark)
                }
                ScrollView {
                    Text(probe.log).font(.body.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .frame(minWidth: 640, minHeight: 420)
            .onAppear { probe.runSaved() }
        }
    }
}

@MainActor @Observable
final class Probe {
    var log = ""
    private let key = "probe.bookmark"
    var hasBookmark: Bool { UserDefaults.standard.data(forKey: key) != nil }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Grant"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: key)
            say("bookmark saved for \(url.path)")
            run(url, source: "panel")
        } catch {
            say("bookmark FAILED: \(error)")
        }
    }

    func runSaved() {
        guard let data = UserDefaults.standard.data(forKey: key) else { say("no bookmark yet: Choose Folder…"); return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            say("bookmark resolved for \(url.path)\(stale ? " (stale)" : "")")
            run(url, source: "bookmark")
        } catch {
            say("bookmark resolve FAILED: \(error)")
        }
    }

    private func run(_ folder: URL, source: String) {
        guard folder.startAccessingSecurityScopedResource() else { say("startAccessing FAILED"); return }
        defer { folder.stopAccessingSecurityScopedResource() }
        var results: [String: String] = ["source": source, "folder": folder.path, "home": NSHomeDirectory()]
        let beads = folder.appendingPathComponent(".beads").path

        let open = BeadsBridge.call(#"{"op":"open","beads_dir":"\#(beads)"}"#)
        results["open"] = open
        say("open → \(open.prefix(160))")
        let handle = (try? JSONSerialization.jsonObject(with: Data(open.utf8)) as? [String: Any])?["handle"] as? Int ?? 0
        let steps: [(String, String)] = [
            ("ready", #"{"op":"ready","handle":\#(handle)}"#),
            ("create", #"{"op":"create","handle":\#(handle),"actor":"sandbox-probe","title":"Made inside the sandbox"}"#),
        ]
        for (name, req) in steps {
            let out = BeadsBridge.call(req)
            results[name] = out
            say("\(name) → \(out.prefix(160))")
        }
        if let created = try? JSONSerialization.jsonObject(with: Data((results["create"] ?? "").utf8)) as? [String: Any],
           let issue = created["issue"] as? [String: Any], let id = issue["id"] as? String {
            for (name, req) in [("update", #"{"op":"update","handle":\#(handle),"actor":"sandbox-probe","id":"\#(id)","new_status":"in_progress"}"#),
                                ("close", #"{"op":"close_issue","handle":\#(handle),"actor":"sandbox-probe","id":"\#(id)","reason":"probe"}"#)] {
                let out = BeadsBridge.call(req)
                results[name] = out
                say("\(name) → \(out.prefix(160))")
            }
        }

        // the fence: nothing outside the grant
        let real = realHome()
        for (name, path) in [("fence.config", "\(real)/.config"), ("fence.dolt", "\(real)/.dolt"),
                             ("fence.ungranted", "\(real)/.cache/beadster/fixtures/one/.beads")] {
            let readable = FileManager.default.isReadableFile(atPath: path)
            let opened = BeadsBridge.call(#"{"op":"open","beads_dir":"\#(path)"}"#)
            results[name] = "readable=\(readable) open=\(opened)"
            say("\(name): readable=\(readable) open → \(opened.prefix(120))")
        }
        write(results)
    }

    private func realHome() -> String {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return NSHomeDirectory() }
        return String(cString: dir)
    }

    private func write(_ results: [String: String]) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("probe-report.json")
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
            say("report → \(url.path)")
        }
    }

    private func say(_ line: String) { log += line + "\n" }
}
