//
//  SSHManager.swift
//  CouchCoder
//
//  Created by ChatGPT on 11/16/25.
//

import Foundation
import Combine
import SwiftSH

@MainActor
final class SSHManager: ObservableObject {
    static let shared = SSHManager()

    private var sessions: [String: SSHConnection] = [:]

    func session(for project: Project) -> SSHConnection {
        if let existing = sessions[project.id] {
            return existing
        }
        let connection = SSHConnection(project: project)
        sessions[project.id] = connection
        return connection
    }

    func closeSession(for project: Project) {
        if let session = sessions.removeValue(forKey: project.id) {
            session.close()
        }
    }
}

@MainActor
final class SSHConnection: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case ready
        case failed(Error)
        
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.connecting, .connecting), (.ready, .ready):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }
    }

    @Published private(set) var state: State = .idle
    var outputPublisher: AnyPublisher<String, Never> {
        outputSubject.eraseToAnyPublisher()
    }
    
    /// Raw terminal output for terminal emulator (not processed/stripped)
    var terminalOutputPublisher: AnyPublisher<Data, Never> {
        terminalOutputSubject.eraseToAnyPublisher()
    }

    let project: Project
    private var session: SSHSession?
    private var shell: SSHShell?
    private var outputSubject = PassthroughSubject<String, Never>()
    private var terminalOutputSubject = PassthroughSubject<Data, Never>()
    private var pendingCommands: [PendingCommand] = []
    private var currentAgent: Agent?
    
    #if DEBUG
    private func log(_ message: String) {
        print("[SSH:\(project.name)] \(message)")
    }
    #else
    private func log(_ message: String) {}
    #endif
    
    // Terminal characteristics used when responding to terminal control sequences
    private let terminalWidth: UInt = 140
    private let terminalHeight: UInt = 40

    init(project: Project) {
        self.project = project
    }

    private enum PendingCommand {
        case line(String)
        case raw(String)
    }

    func connectIfNeeded() async {
        switch state {
        case .ready, .connecting:
            return
        default:
            await connect()
        }
    }

    private func connect() async {
        state = .connecting
        log("Connecting…")

        do {
            let sshSession = try SSHSession(host: AppConfig.sshHost, port: AppConfig.sshPort)
            sshSession.setCallbackQueue(queue: .main)

            try await sshSession.connectAsync()
            let privateKeyData = Data(AppConfig.sshPrivateKey.utf8)
            let challenge = AuthenticationChallenge.byPublicKeyFromMemory(
                username: AppConfig.sshUsername,
                password: AppConfig.sshPrivateKeyPassphrase ?? "",
                publicKey: nil,
                privateKey: privateKeyData
            )
            try await sshSession.authenticateAsync(challenge)

            // Use original working configuration - xterm-256color without environment variables
            // The cursor position error from codex is harmless - codex will still work
            let terminal = Terminal("xterm-256color", width: terminalWidth, height: terminalHeight)
            let shell = try SSHShell(session: sshSession, terminal: terminal)
            shell.withCallback { [weak self] stdout, stderr in
                guard let self = self else { return }
                
                // Always send raw data to terminal emulator
                if let stdout, !stdout.isEmpty {
                    if let data = stdout.data(using: .utf8) {
                        self.terminalOutputSubject.send(data)
                    }
                }
                if let stderr, !stderr.isEmpty {
                    if let data = stderr.data(using: .utf8) {
                        self.terminalOutputSubject.send(data)
                    }
                }
                
                // For Codex agent, skip text output (terminal emulator handles it)
                // For other agents, send processed text to message bubbles
                if self.currentAgent == .codex {
                    // Skip outputSubject for Codex - terminal emulator handles TUI
                } else {
                    if var stdout, !stdout.isEmpty {
                        stdout = self.handleTerminalSequences(in: stdout)
                        if !stdout.isEmpty {
                            self.outputSubject.send(stdout)
                        }
                    }
                    if var stderr, !stderr.isEmpty {
                        stderr = self.handleTerminalSequences(in: stderr)
                        if !stderr.isEmpty {
                            self.outputSubject.send(stderr)
                        }
                    }
                }
            }

            try await shell.openAsync()
            shell.write("cd \(project.path)\n")

            self.session = sshSession
            self.shell = shell
            state = .ready
            log("Connection ready")
            flushPendingCommands()
        } catch {
            print("SSH Connection Error: \(error)")
            print("Error details: \(error.localizedDescription)")
            state = .failed(error)
        }
    }

    func send(line: String) async {
        await connectIfNeeded()
        guard case .ready = state else {
            pendingCommands.append(.line(line))
            log("send(line:) queued – not ready")
            return
        }

        writeLine(line)
    }

    func send(raw data: String) async {
        await connectIfNeeded()
        guard case .ready = state else {
            pendingCommands.append(.raw(data))
            log("send(raw:) queued – not ready")
            return
        }

        writeRaw(data)
    }

    func close() {
        shell?.close(nil)
        session?.disconnect(nil)
        shell = nil
        session = nil
        state = .idle
    }
    
    /// Set the current agent (affects output routing)
    func setAgent(_ agent: Agent) {
        currentAgent = agent
        log("Current agent set to: \(agent.displayName)")
    }
    
    /// Resize the PTY terminal
    func resize(cols: UInt, rows: UInt) async {
        // SwiftSH doesn't expose PTY resize directly, but we can track it
        // for future implementation if needed
        log("Terminal resize requested: \(cols)x\(rows)")
    }
    
    /// Write raw data to the shell (for terminal input)
    func writeRaw(_ data: Data) async {
        await connectIfNeeded()
        guard case .ready = state, let shell else { return }
        
        if let string = String(data: data, encoding: .utf8) {
            shell.write(string)
        }
    }
    
    private func handleTerminalSequences(in text: String) -> String {
        var processed = text
        
        // Respond to cursor position queries so interactive tools like Codex don't error out
        let cursorQuery = "\u{001B}[6n"
        while let range = processed.range(of: cursorQuery) {
            processed.removeSubrange(range)
            sendCursorPositionReport()
        }
        
        return processed
    }
    
    private func sendCursorPositionReport() {
        guard let shell else { return }
        let report = "\u{001B}[\(terminalHeight);\(terminalWidth)R"
        shell.write(report)
    }

    private func writeLine(_ line: String) {
        guard let shell else { return }
        let needsTerminator = !line.hasSuffix("\n") && !line.hasSuffix("\r")
        let payload = needsTerminator ? line + "\r\n" : line
        shell.write(payload)
        log("send(line: \(line.trimmingCharacters(in: .whitespacesAndNewlines)))")
    }

    private func writeRaw(_ data: String) {
        guard let shell else { return }
        shell.write(data)
        let printable = data.replacingOccurrences(of: "\n", with: "\\n")
        if data == "\u{0003}" {
            log("send(raw: <CTRL+C>)")
        } else {
            log("send(raw: \(printable))")
        }
    }

    private func flushPendingCommands() {
        guard case .ready = state, !pendingCommands.isEmpty else { return }
        let queued = pendingCommands
        pendingCommands.removeAll()
        for command in queued {
            switch command {
            case .line(let line):
                writeLine(line)
            case .raw(let raw):
                writeRaw(raw)
            }
        }
    }
    
    /// Execute a command and return its output (uses a separate SSH command channel)
    func executeCommand(_ command: String) async throws -> String {
        guard let session = session else {
            throw NSError(domain: "SSHConnection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        
        let commandChannel = try SSHCommand(session: session)
        return try await commandChannel.executeAsync(command)
    }
}
