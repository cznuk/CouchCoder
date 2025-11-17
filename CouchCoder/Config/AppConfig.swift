//
//  AppConfig.swift
//  CouchCoder
//
//  Created by ChatGPT on 11/16/25.
//

import Foundation

/// Static configuration source for CouchCoder that reads from the bundled `.env` file.
enum AppConfig {
    private static let env = EnvironmentValues()

    static let sshHost = env.require(.sshHost)
    static let sshPort: UInt16 = env.requireUInt16(.sshPort, defaultValue: 22)
    static let sshUsername = env.require(.sshUsername)
    static let sshPrivateKey: String = {
        if let inlineKey = env.optional(.sshPrivateKey), !inlineKey.isEmpty {
            return ensureTrailingNewline(for: inlineKey)
        }

        if let keyPath = env.optional(.sshPrivateKeyPath) {
            do {
                let contents = try String(contentsOfFile: keyPath, encoding: .utf8)
                return ensureTrailingNewline(for: contents)
            } catch {
                fatalError("AppConfig: Failed to read SSH private key at \(keyPath): \(error)")
            }
        }

        fatalError("AppConfig: Missing SSH private key. Provide SSH_PRIVATE_KEY or SSH_PRIVATE_KEY_PATH in .env.")
    }()
    static let sshPrivateKeyPassphrase: String? = env.optional(.sshPrivateKeyPassphrase)
    static let projectsBasePath = env.require(.projectsBasePath)
    static let defaultAgent: Agent = {
        let raw = env.require(.defaultAgent).lowercased()
        return Agent(rawValue: raw) ?? .codex
    }()
    static let deviceUDID = env.require(.deviceUDID)
    static let developmentTeam = env.require(.developmentTeam)
    static let gitOneLiner = env.require(.gitOneLiner)
    static let keychainPassword = env.require(.keychainPassword)
    static let hiddenProjectsStoreKey = env.require(.hiddenProjectsKey)
    static let pinnedProjectsStoreKey = env.require(.pinnedProjectsKey)
    static let pinnedProjectsMaxCount = env.requireInt(.pinnedProjectsMaxCount, defaultValue: 9)
    static let projectAccentColorsStoreKey = env.require(.projectAccentColorsKey)
    static let newProjectBundleIdPrefix = env.require(.newProjectBundlePrefix)
    static let newProjectDeploymentTarget = env.require(.newProjectDeploymentTarget)

    static func xcodebuildInstallCommand(scheme: String) -> String {
        "!xcodebuild -scheme \(scheme) -destination 'platform=iOS,id=\(deviceUDID)' build install"
    }

    private static func ensureTrailingNewline(for key: String) -> String {
        key.hasSuffix("\n") ? key : key + "\n"
    }
}

private struct EnvironmentValues {
    private let values: [String: String]

    init(bundle: Bundle = .main) {
        var combined = ProcessInfo.processInfo.environment
        let fileValues = DotEnvFileLoader(bundle: bundle).load()
        combined.merge(fileValues) { _, new in new }
        values = combined
    }

    func require(_ key: ConfigKey) -> String {
        guard let value = optional(key) else {
            fatalError("AppConfig: Missing value for \(key.rawValue) in .env. See README for setup details.")
        }
        return value
    }

    func requireInt(_ key: ConfigKey, defaultValue: Int? = nil) -> Int {
        guard let raw = optional(key) else {
            guard let defaultValue else {
                fatalError("AppConfig: Missing integer value for \(key.rawValue).")
            }
            return defaultValue
        }

        guard let value = Int(raw) else {
            fatalError("AppConfig: \(key.rawValue) must be an integer, got '\(raw)'.")
        }
        return value
    }

    func requireUInt16(_ key: ConfigKey, defaultValue: UInt16? = nil) -> UInt16 {
        guard let raw = optional(key) else {
            guard let defaultValue else {
                fatalError("AppConfig: Missing UInt16 value for \(key.rawValue).")
            }
            return defaultValue
        }

        guard let value = UInt16(raw) else {
            fatalError("AppConfig: \(key.rawValue) must be a UInt16-compatible integer, got '\(raw)'.")
        }
        return value
    }

    func optional(_ key: ConfigKey) -> String? {
        guard let raw = values[key.rawValue] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct DotEnvFileLoader {
    private let bundle: Bundle

    init(bundle: Bundle) {
        self.bundle = bundle
    }

    func load() -> [String: String] {
        var result: [String: String] = [:]
        for fileName in [".env", ".env.local"] {
            guard let url = locateFile(named: fileName) else { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let parsed = parse(contents)
            result.merge(parsed) { _, new in new }
        }
        return result
    }

    private func locateFile(named fileName: String) -> URL? {
        if let url = bundle.url(forResource: fileName, withExtension: nil) {
            return url
        }

        if let url = bundle.url(forResource: fileName, withExtension: nil, subdirectory: "Config") {
            return url
        }

        if let resourcePath = bundle.resourcePath {
            let rootCandidate = URL(fileURLWithPath: resourcePath).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: rootCandidate.path) {
                return rootCandidate
            }

            let configCandidate = URL(fileURLWithPath: resourcePath)
                .appendingPathComponent("Config")
                .appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: configCandidate.path) {
                return configCandidate
            }
        }

        return nil
    }

    private func parse(_ rawText: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in rawText.components(separatedBy: .newlines) {
            guard let (key, value) = parseLine(line) else { continue }
            values[key] = value
        }
        return values
    }

    private func parseLine(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        guard let equalsIndex = trimmed.firstIndex(of: "=") else { return nil }

        let keyPart = trimmed[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyPart.isEmpty else { return nil }

        var valuePart = String(trimmed[trimmed.index(after: equalsIndex)...])
        valuePart = stripInlineComment(valuePart)
        valuePart = valuePart.trimmingCharacters(in: .whitespacesAndNewlines)

        let (unquoted, wasQuoted) = unquote(valuePart)
        let finalValue = wasQuoted ? unescape(unquoted) : unquoted
        return (keyPart, finalValue)
    }

    private func stripInlineComment(_ value: String) -> String {
        var builder = ""
        var isEscaping = false
        var quotedBy: Character?

        for character in value {
            if isEscaping {
                builder.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                builder.append(character)
                continue
            }

            if character == "#", quotedBy == nil {
                break
            }

            if character == "\"" || character == "'" {
                if quotedBy == character {
                    quotedBy = nil
                } else if quotedBy == nil {
                    quotedBy = character
                }
            }

            builder.append(character)
        }

        if isEscaping {
            builder.append("\\")
        }

        return builder
    }

    private func unquote(_ value: String) -> (String, Bool) {
        guard value.count >= 2 else { return (value, false) }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            let trimmed = String(value.dropFirst().dropLast())
            return (trimmed, true)
        }
        return (value, false)
    }

    private func unescape(_ value: String) -> String {
        var result = ""
        var isEscaping = false

        for character in value {
            if isEscaping {
                switch character {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "\"": result.append("\"")
                case "'": result.append("'")
                case "\\": result.append("\\")
                default:
                    result.append(character)
                }
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
            } else {
                result.append(character)
            }
        }

        if isEscaping {
            result.append("\\")
        }

        return result
    }
}

private enum ConfigKey: String {
    case sshHost = "SSH_HOST"
    case sshPort = "SSH_PORT"
    case sshUsername = "SSH_USERNAME"
    case sshPrivateKey = "SSH_PRIVATE_KEY"
    case sshPrivateKeyPath = "SSH_PRIVATE_KEY_PATH"
    case sshPrivateKeyPassphrase = "SSH_PRIVATE_KEY_PASSPHRASE"
    case projectsBasePath = "PROJECTS_BASE_PATH"
    case defaultAgent = "DEFAULT_AGENT"
    case deviceUDID = "DEVICE_UDID"
    case developmentTeam = "DEVELOPMENT_TEAM"
    case gitOneLiner = "GIT_ONE_LINER"
    case keychainPassword = "KEYCHAIN_PASSWORD"
    case hiddenProjectsKey = "HIDDEN_PROJECTS_KEY"
    case pinnedProjectsKey = "PINNED_PROJECTS_KEY"
    case pinnedProjectsMaxCount = "PINNED_PROJECTS_MAX_COUNT"
    case projectAccentColorsKey = "PROJECT_ACCENT_COLORS_KEY"
    case newProjectBundlePrefix = "NEW_PROJECT_BUNDLE_PREFIX"
    case newProjectDeploymentTarget = "NEW_PROJECT_DEPLOYMENT_TARGET"
}
