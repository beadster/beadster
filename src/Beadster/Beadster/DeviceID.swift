//
//  DeviceID.swift
//  Beadster
//
//  Hardware-based device identification using IOPlatformUUID
//

import Foundation
import IOKit

class DeviceID {
    static let shared = DeviceID()

    private let configPath: URL
    private var cachedDeviceId: String?

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let beadsterDir = homeDir.appendingPathComponent(".beadster")
        configPath = beadsterDir.appendingPathComponent("device.json")

        // ensure .beadster directory exists
        try? FileManager.default.createDirectory(at: beadsterDir, withIntermediateDirectories: true)
    }

    // get or create device ID
    func getDeviceId() -> String {
        if let cached = cachedDeviceId {
            return cached
        }

        // try to load from config file
        if let config = loadConfig() {
            cachedDeviceId = config.deviceId
            return config.deviceId
        }

        // generate new device ID
        let hardwareUuid = getHardwareUUID()
        let deviceId = generateDeviceId(from: hardwareUuid)

        // save config
        let config = DeviceConfig(
            deviceId: deviceId,
            hardwareUuid: hardwareUuid,
            createdAt: Int(Date().timeIntervalSince1970)
        )
        saveConfig(config)

        cachedDeviceId = deviceId
        return deviceId
    }

    // get hardware UUID using IOKit
    private func getHardwareUUID() -> String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        defer { IOObjectRelease(platformExpert) }

        guard platformExpert != 0 else {
            return fallbackUUID()
        }

        guard let uuidRef = IORegistryEntryCreateCFProperty(
            platformExpert,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return fallbackUUID()
        }

        guard let uuid = uuidRef.takeRetainedValue() as? String else {
            return fallbackUUID()
        }

        return uuid
    }

    // fallback UUID using hostname + username
    private func fallbackUUID() -> String {
        let hostname = ProcessInfo.processInfo.hostName
        let username = NSUserName()
        return "\(hostname)_\(username)"
    }

    // generate device ID from hardware UUID
    private func generateDeviceId(from uuid: String) -> String {
        // hash UUID to create shorter ID
        let hash = uuid.data(using: .utf8)!.sha256Hex()
        let shortHash = String(hash.prefix(16))
        return "device_\(shortHash)"
    }

    // load config from ~/.beadster/device.json
    private func loadConfig() -> DeviceConfig? {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: configPath)
            let config = try JSONDecoder().decode(DeviceConfig.self, from: data)
            return config
        } catch {
            print("Failed to load device config: \(error)")
            return nil
        }
    }

    // save config to ~/.beadster/device.json
    private func saveConfig(_ config: DeviceConfig) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: configPath, options: .atomic)
            print("Saved device config to \(configPath.path)")
        } catch {
            print("Failed to save device config: \(error)")
        }
    }
}

// device config structure
struct DeviceConfig: Codable {
    let deviceId: String
    let hardwareUuid: String
    let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case hardwareUuid = "hardware_uuid"
        case createdAt = "created_at"
    }
}

// SHA256 hash extension
extension Data {
    func sha256Hex() -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// need to import CommonCrypto for SHA256
import CommonCrypto
