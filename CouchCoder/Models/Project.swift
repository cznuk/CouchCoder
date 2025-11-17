//
//  Project.swift
//  CouchCoder
//
//  Created by ChatGPT on 11/16/25.
//

import Foundation

struct Project: Identifiable, Hashable, Codable {
    var id: String { path }

    let name: String
    let path: String
    var isHidden: Bool
    var isPinned: Bool
    var accentColor: ProjectAccentColor
    var lastActivity: Date?
    var lastMessagePreview: String?

    init(
        name: String,
        path: String,
        isHidden: Bool = false,
        isPinned: Bool = false,
        accentColor: ProjectAccentColor = .sky,
        lastActivity: Date? = nil,
        lastMessagePreview: String? = nil
    ) {
        self.name = name
        self.path = path
        self.isHidden = isHidden
        self.isPinned = isPinned
        self.accentColor = accentColor
        self.lastActivity = lastActivity
        self.lastMessagePreview = lastMessagePreview
    }
}

enum ProjectAccentColor: String, Codable, CaseIterable {
    case sky
    case grape
    case mango
    case mint
    case rose
    case twilight

    func next() -> ProjectAccentColor {
        let all = Self.allCases
        guard let currentIndex = all.firstIndex(of: self) else {
            return all.first ?? .sky
        }
        let nextIndex = all.index(after: currentIndex)
        return nextIndex < all.endIndex ? all[nextIndex] : all.first ?? .sky
    }
}
