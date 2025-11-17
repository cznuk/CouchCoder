//
//  Message.swift
//  CouchCoder
//
//  Created by ChatGPT on 11/16/25.
//

import Foundation

enum MessageSender: String, Codable {
    case user
    case terminal
}

struct Message: Identifiable, Codable, Hashable {
    let id: UUID
    let sender: MessageSender
    var text: String
    let timestamp: Date
    var isStreaming: Bool

    init(id: UUID = UUID(), sender: MessageSender, text: String, timestamp: Date = .now, isStreaming: Bool = false) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

