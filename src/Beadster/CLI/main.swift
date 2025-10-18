import Foundation

let configPath = "\(NSHomeDirectory())/.beadster/config.json"

guard FileManager.default.fileExists(atPath: configPath) else {
    print("❌ Config file not found at \(configPath)")
    print("")
    print("Create ~/.beadster/config.json with:")
    print("""
    {
      "apiKey": "your-api-key",
      "apiUrl": "https://api.beadster.com",
      "sources": [
        {
          "name": "my-project",
          "path": "/Users/you/projects/my-project"
        }
      ]
    }
    """)
    exit(1)
}

do {
    let daemon = try SyncDaemon(configPath: configPath)
    await daemon.start()
} catch {
    print("❌ Error: \(error)")
    exit(1)
}
