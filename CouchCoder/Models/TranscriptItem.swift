//
//  TranscriptItem.swift
//  CouchCoder
//
//  Created by AI Assistant on 11/17/25.
//

import Foundation
import UIKit

/// Represents an item in the chat transcript - either a user message or a terminal snapshot
enum TranscriptItem: Identifiable {
    case user(id: UUID, text: String)
    case frame(id: UUID, image: UIImage)
    
    var id: UUID {
        switch self {
        case .user(let id, _), .frame(let id, _):
            return id
        }
    }
}


