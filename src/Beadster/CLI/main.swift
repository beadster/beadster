import Foundation

@main
struct BeadsterCLI {
    static func main() async throws {
        let configPath = "\(NSHomeDirectory())/.beadster/config.json"

        guard FileManager.default.fileExists(atPath: configPath) else {
            print("❌ Config not found at \(configPath)")
            print("Create config file with:")
            print("""
            {
              "apiKey": "your-api-key",
              "apiUrl": "https://beadster-dev-api.systemoperator.workers.dev",
              "sources": [
                {
                  "name": "my-project",
                  "path": "/path/to/project"
                }
              ]
            }
            """)
            return
        }

        let daemon = try CLISyncDaemon(configPath: configPath)
        await daemon.start()
    }
}
