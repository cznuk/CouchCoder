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
        .overlay(alignment: .bottom) {
            bottomActionOverlay
        }
        .onAppear {
            viewModel.start()
        }
    }

    @ViewBuilder
    private var bottomActionOverlay: some View {
        if viewModel.hasBuildError || viewModel.pendingURLString != nil {
            VStack(spacing: 12) {
                if let urlString = viewModel.pendingURLString {
                    urlBanner(for: urlString)
                }
                if viewModel.hasBuildError {
                    buildErrorButton
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
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

    private func urlBanner(for urlString: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Detected URL", systemImage: "link")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Button {
                    viewModel.dismissDetectedURLBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .padding(6)
                        .background(Color.black.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Text(urlString)
                .font(.caption.monospaced())
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Button {
                    viewModel.copyDetectedURL()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.footnote.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.openDetectedURL()
                } label: {
                    Label("Open", systemImage: "safari")
                        .font(.footnote.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6, y: 2)
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
