//
//  Agent.swift
//  CouchCoder
//
//  Created by ChatGPT on 11/16/25.
//

import Foundation

enum Agent: String, CaseIterable, Identifiable, Codable {
    case codex = "codex"
    case cursor = "cursor-agent"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .cursor:
            return "Cursor"
        }
    }
    
    var launchCommand: String {
        switch self {
        case .codex:
            return "env TERM=dumb COLORTERM= NO_COLOR=1 codex"
        case .cursor:
            return "env TERM=dumb COLORTERM= NO_COLOR=1 cursor-agent"
        }
    }
}

