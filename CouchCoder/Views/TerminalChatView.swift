//
//  TerminalChatView.swift
//  CouchCoder
//
//  Created by ChatGPT on 11/16/25.
//

import SwiftUI

struct TerminalChatView: View {
    @StateObject private var viewModel: TerminalSessionViewModel

    init(project: Project) {
        _viewModel = StateObject(wrappedValue: TerminalSessionViewModel(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Full-screen terminal
            TerminalPaneView(bridge: viewModel.terminalBridge)
            
            // Build error copy button
            if viewModel.hasBuildError {
                buildErrorButton
            }
        }
        .navigationTitle(viewModel.project.name)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    viewModel.launchCodex()
                } label: {
                    Label("Codex", systemImage: "c.circle")
                }
                
                Button {
                    viewModel.buildAndInstall()
                } label: {
                    Label("Build", systemImage: "hammer")
                }

                Button {
                    viewModel.sendGitCommand()
                } label: {
                    Label("Git", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                ConnectionBadge(state: viewModel.state)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.hasBuildError {
                buildErrorButton
                    .padding()
                    .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            viewModel.start()
        }
    }
    
    private var buildErrorButton: some View {
        Button {
            viewModel.copyBuildErrors()
        } label: {
            HStack {
                Image(systemName: "doc.on.doc")
                Text("Copy Build Errors")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.red)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

}

private struct ConnectionBadge: View {
    let state: SSHConnection.State

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
//            Text(label)
//                .font(.footnote)
        }
    }

    private var label: String {
        switch state {
        case .ready:
            return "Connected"
        case .connecting:
            return "Connecting…"
        case .failed(_):
            return "Retry required"
        case .idle:
            return "Idle"
        }
    }

    private var color: Color {
        switch state {
        case .ready:
            return .green
        case .connecting:
            return .yellow
        case .failed(_):
            return .red
        case .idle:
            return .gray
        }
    }
}

#Preview {
    TerminalChatView(project: Project(name: "BottleBank", path: "~/Projects/BottleBank"))
}
