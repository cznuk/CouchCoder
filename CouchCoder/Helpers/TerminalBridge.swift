//
//  TerminalBridge.swift
//  CouchCoder
//
//  Created by AI Assistant on 11/17/25.
//

import Foundation
import SwiftTerm
import UIKit
import Combine

/// Bridges SwiftTerm's TerminalView with SSH connection
@MainActor
final class TerminalBridge: NSObject, TerminalViewDelegate {
    private let ssh: SSHConnection
    private weak var terminalView: TerminalView?
    private var cancellables = Set<AnyCancellable>()
    
    init(ssh: SSHConnection) {
        self.ssh = ssh
        super.init()
        
        // Subscribe to SSH output and feed it to the terminal
        ssh.terminalOutputPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] data in
                let bytes = Array(data)
                self?.terminalView?.feed(byteArray: bytes[...])
            }
            .store(in: &cancellables)
    }
    
    func attach(terminalView: TerminalView) {
        self.terminalView = terminalView
        Task {
            await start()
        }
    }
    
    private func start() async {
        await ssh.connectIfNeeded()
    }
    
    // MARK: - TerminalViewDelegate
    
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        Task {
            await ssh.resize(cols: UInt(newCols), rows: UInt(newRows))
        }
    }
    
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        Task {
            await ssh.writeRaw(Data(data))
        }
    }
    
    func scrolled(source: TerminalView, position: Double) {
        // Optional: handle scroll events
    }
    
    func setTerminalTitle(source: TerminalView, title: String) {
        // Optional: handle title changes
    }
    
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Optional: track directory changes
    }
    
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        // Optional: handle link clicks
    }
    
    func clipboardCopy(source: TerminalView, content: Data) {
        // Convert Data to String and copy to pasteboard
        let text = String(data: content, encoding: .utf8) ?? String(decoding: content, as: UTF8.self)
        UIPasteboard.general.string = text
        #if DEBUG
        print("[TerminalBridge] Copied to clipboard: \(text.prefix(50))...")
        #endif
    }
    
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        // Optional: handle range changes for rendering optimization
    }
    
    // MARK: - Public helpers
    
    /// Send text to the terminal without appending a newline
    func sendText(_ text: String) {
        guard let term = terminalView else { return }
        for scalar in text.unicodeScalars {
            term.send(txt: String(scalar))
        }
    }
    
    /// Send a prompt to the terminal (types it in and presses Enter)
    func sendPrompt(_ text: String) {
        sendText(text)
        terminalView?.send(txt: "\r")
    }
    
    /// Capture a snapshot of the current terminal state as an image
    func snapshot() -> UIImage? {
        guard let view = terminalView, view.bounds.width > 0, view.bounds.height > 0 else {
            return nil
        }
        
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        return renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
    }
}
