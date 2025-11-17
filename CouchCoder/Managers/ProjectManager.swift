//
//  ProjectManager.swift
//  CouchCoder
//
//  Created by ChatGPT on 11/16/25.
//

import Foundation
import Combine
import SwiftSH

@MainActor
final class ProjectManager: ObservableObject {
    static let shared = ProjectManager()

    @Published private(set) var projects: [Project] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private let hiddenStore = HiddenProjectStore()
    private let pinnedStore = PinnedProjectStore()
    private let accentColorStore = ProjectAccentColorStore()

    var visibleProjects: [Project] {
        projects.filter { !$0.isHidden }
    }

    var hiddenProjects: [Project] {
        projects.filter(\.isHidden)
    }

    var pinnedProjects: [Project] {
        let order = pinnedStore.pinnedProjects
        let lookup = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return visibleProjects
            .filter(\.isPinned)
            .sorted { lhs, rhs in
                let lhsIndex = lookup[lhs.name] ?? Int.max
                let rhsIndex = lookup[rhs.name] ?? Int.max
                if lhsIndex == rhsIndex {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhsIndex < rhsIndex
            }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let names = try await RemoteShell.listDirectories(at: AppConfig.projectsBasePath)
            let hidden = hiddenStore.hiddenProjects
            let pinned = Set(pinnedStore.pinnedProjects)
            let mapped = names.map { name -> Project in
                let accentColor = accentColorStore.color(for: name) ?? .sky
                var project = Project(
                    name: name,
                    path: "\(AppConfig.projectsBasePath)/\(name)",
                    isHidden: hidden.contains(name),
                    isPinned: pinned.contains(name),
                    accentColor: accentColor
                )
                if let existing = projects.first(where: { $0.id == project.id }) {
                    project.lastActivity = existing.lastActivity
                    project.lastMessagePreview = existing.lastMessagePreview
                }
                return project
            }
            let sorted = mapped.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            projects = sorted
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleHidden(for project: Project) {
        setHidden(!project.isHidden, for: project)
    }

    func setHidden(_ hidden: Bool, for project: Project) {
        if hidden {
            hiddenStore.add(project.name)
        } else {
            hiddenStore.remove(project.name)
        }
        projects = projects.map { current in
            guard current.id == project.id else { return current }
            var updated = current
            updated.isHidden = hidden
            return updated
        }
    }

    func setPinned(_ pinned: Bool, for project: Project) {
        if pinned {
            pinnedStore.add(project.name)
        } else {
            pinnedStore.remove(project.name)
        }

        projects = projects.map { current in
            guard current.id == project.id else { return current }
            var updated = current
            updated.isPinned = pinned
            return updated
        }
    }

    func updatePreview(for project: Project, text: String, timestamp: Date) {
        projects = projects.map { current in
            guard current.id == project.id else { return current }
            var updated = current
            updated.lastMessagePreview = text
            updated.lastActivity = timestamp
            return updated
        }
    }

    func advanceAccentColor(for project: Project) {
        let nextColor = project.accentColor.next()
        accentColorStore.set(nextColor, for: project.name)

        projects = projects.map { current in
            guard current.id == project.id else { return current }
            var updated = current
            updated.accentColor = nextColor
            return updated
        }
    }

    func createProject(request: NewProjectRequest) async throws {
        do {
            try await RemoteShell.createProject(request: request)
            await refresh()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
}

extension ProjectManager {
    struct NewProjectRequest {
        let displayName: String
        let folderName: String
        let targetName: String
        let bundleIDPrefix: String
        let bundleIdentifier: String
        let deploymentTarget: String
    }
}

private final class HiddenProjectStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hiddenProjects: Set<String> {
        get {
            let array = defaults.array(forKey: AppConfig.hiddenProjectsStoreKey) as? [String] ?? []
            return Set(array)
        }
        set {
            defaults.set(Array(newValue), forKey: AppConfig.hiddenProjectsStoreKey)
        }
    }

    func add(_ name: String) {
        var current = hiddenProjects
        current.insert(name)
        hiddenProjects = current
    }

    func remove(_ name: String) {
        var current = hiddenProjects
        current.remove(name)
        hiddenProjects = current
    }
}

private final class PinnedProjectStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pinnedProjects: [String] {
        get {
            defaults.stringArray(forKey: AppConfig.pinnedProjectsStoreKey) ?? []
        }
        set {
            defaults.set(newValue, forKey: AppConfig.pinnedProjectsStoreKey)
        }
    }

    func add(_ name: String) {
        var current = pinnedProjects.filter { $0 != name }
        current.insert(name, at: 0)
        if current.count > AppConfig.pinnedProjectsMaxCount {
            current = Array(current.prefix(AppConfig.pinnedProjectsMaxCount))
        }
        pinnedProjects = current
    }

    func remove(_ name: String) {
        pinnedProjects = pinnedProjects.filter { $0 != name }
    }
}

private final class ProjectAccentColorStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var storedColors: [String: String] {
        get {
            defaults.dictionary(forKey: AppConfig.projectAccentColorsStoreKey) as? [String: String] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: AppConfig.projectAccentColorsStoreKey)
        }
    }

    func color(for projectName: String) -> ProjectAccentColor? {
        guard
            let raw = storedColors[projectName],
            let color = ProjectAccentColor(rawValue: raw)
        else {
            return nil
        }
        return color
    }

    func set(_ color: ProjectAccentColor, for projectName: String) {
        var current = storedColors
        current[projectName] = color.rawValue
        storedColors = current
    }
}

enum RemoteShell {
    private static let successMarker = "__COUCHCODER_SUCCESS__"
    private static let errorMarkerPrefix = "__COUCHCODER_ERROR__:"

    static func listDirectories(at path: String) async throws -> [String] {
        let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
        let command = #"cd "\#(escapedPath)" && ls -1 -d */"#
        let output = try await execute(command: command)
        return output
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                var name = line.trimmingCharacters(in: .whitespacesAndNewlines)
                name = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return name
            }
            .filter { !$0.isEmpty }
    }

    /// Attempts to detect the first available Xcode scheme in a project directory.
    /// Returns nil if no scheme is found or if detection fails.
    static func detectScheme(in projectPath: String) async -> String? {
        do {
            let escapedPath = projectPath.replacingOccurrences(of: "\"", with: "\\\"")
            
            // First, find .xcodeproj or .xcworkspace files
            let findCommand = #"cd "\#(escapedPath)" && (find . -maxdepth 1 -name "*.xcworkspace" | head -1 || find . -maxdepth 1 -name "*.xcodeproj" | head -1)"#
            let projectFile = try await execute(command: findCommand).trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !projectFile.isEmpty else { return nil }
            
            // Determine if it's a workspace or project
            let isWorkspace = projectFile.hasSuffix(".xcworkspace")
            let flag = isWorkspace ? "-workspace" : "-project"
            
            // Get the scheme list - look for the first scheme after "Schemes:" line
            let listCommand = "cd \"\(escapedPath)\" && xcodebuild -list \(flag) \"\(projectFile)\" 2>/dev/null | awk '/^Schemes:/{flag=1;next} flag && /^[[:space:]]*[^[:space:]]/{print $1;exit}'"
            let scheme = try await execute(command: listCommand).trimmingCharacters(in: .whitespacesAndNewlines)
            
            return scheme.isEmpty ? nil : scheme
        } catch {
            return nil
        }
    }

    static func createProject(request: ProjectManager.NewProjectRequest) async throws {
        let basePath = escapeForDoubleQuotes(AppConfig.projectsBasePath)
        let folderName = escapeForDoubleQuotes(request.folderName)
        let targetDirectory = escapeForDoubleQuotes(request.targetName)
        let displayName = request.displayName.replacingOccurrences(of: "\"", with: "\\\"")
        let folderDisplayName = request.folderName.replacingOccurrences(of: "\"", with: "\\\"")
        let projectYAML = """
name: \(request.targetName)
options:
  bundleIdPrefix: \(request.bundleIDPrefix)

targets:
  \(request.targetName):
    type: application
    platform: iOS
    deploymentTarget: "\(request.deploymentTarget)"
    sources:
      - \(request.targetName)
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: \(request.bundleIdentifier)
      GENERATE_INFOPLIST_FILE: YES
      DEVELOPMENT_TEAM: \(AppConfig.developmentTeam)
      CODE_SIGN_STYLE: Automatic
"""
        let appFile = """
import SwiftUI

@main
struct \(request.targetName)App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
"""
        let contentView = """
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 42))
            Text("Hello from \(displayName)!")
                .font(.title2.weight(.semibold))
            Text("Generated by CouchCoder with XcodeGen")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ContentView()
}
"""

        let script = """
set -euo pipefail
exec 2>&1
trap 'echo "\(errorMarkerPrefix)Project creation failed. Check your Mac for more details."' ERR

# Ensure Homebrew-installed binaries (like XcodeGen) are on PATH even in non-login shells.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "\(errorMarkerPrefix)XcodeGen isn't installed on your Mac. Run 'brew install xcodegen' first."
  exit 1
fi

cd "\(basePath)"
if [ -e "\(folderName)" ]; then
  echo "\(errorMarkerPrefix)A project named \(folderDisplayName) already exists."
  exit 1
fi

mkdir -p "\(folderName)/\(targetDirectory)"
cat <<'YAML' > "\(folderName)/project.yml"
\(projectYAML)
YAML

cat <<'SWIFT' > "\(folderName)/\(targetDirectory)/\(request.targetName)App.swift"
\(appFile)
SWIFT

cat <<'SWIFT' > "\(folderName)/\(targetDirectory)/ContentView.swift"
\(contentView)
SWIFT

cd "\(folderName)"
xcodegen >/dev/null
echo "\(successMarker)"
"""

        let command = bashCommand(for: script)
        let output = try await execute(command: command)
        try validateSuccess(from: output)
    }

    static func execute(command: String) async throws -> String {
        let session = try SSHSession(host: AppConfig.sshHost, port: AppConfig.sshPort)
        session.setCallbackQueue(queue: .main)
        try await session.connectAsync()
        let privateKeyData = Data(AppConfig.sshPrivateKey.utf8)
        let challenge = AuthenticationChallenge.byPublicKeyFromMemory(
            username: AppConfig.sshUsername,
            password: AppConfig.sshPrivateKeyPassphrase ?? "",
            publicKey: nil,
            privateKey: privateKeyData
        )
        try await session.authenticateAsync(challenge)

        let commandChannel = try SSHCommand(session: session)
        let output = try await commandChannel.executeAsync(command)
        session.disconnect(nil)
        return output
    }

    private static func escapeForDoubleQuotes(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func bashCommand(for script: String) -> String {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\"'\"'")
        return "bash -lc '\(escaped)'"
    }

    private static func validateSuccess(from output: String) throws {
        guard output.contains(successMarker) else {
            if let message = parseError(from: output) {
                throw RemoteShellError.commandFailed(message)
            } else {
                throw RemoteShellError.commandFailed("Project creation failed. Please check your Mac's terminal output.")
            }
        }
    }

    private static func parseError(from output: String) -> String? {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
        for line in lines.reversed() {
            if let range = line.range(of: errorMarkerPrefix) {
                let message = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !message.isEmpty {
                    return message
                }
            }
        }
        return nil
    }
}

enum RemoteShellError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}
