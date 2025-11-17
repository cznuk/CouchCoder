//
//  ANSIParser.swift
//  CouchCoder
//
//  Created by ChatGPT on 11/16/25.
//

import Foundation

enum ANSIParser {
    private static let csiPattern = #"\u001B\[[0-9;?]*[ -/]*[@-~]"#
    private static let oscPattern = #"\u001B\][^\u0007]*\u0007"#
    private static let csiRegex = try? NSRegularExpression(pattern: csiPattern, options: [])
    private static let oscRegex = try? NSRegularExpression(pattern: oscPattern, options: [])

    static func strip(from text: String) -> String {
        var working = text

        if let csiRegex {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            working = csiRegex.stringByReplacingMatches(in: working, range: range, withTemplate: "")
        }

        if let oscRegex {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            working = oscRegex.stringByReplacingMatches(in: working, range: range, withTemplate: "")
        }

        return working.replacingOccurrences(of: "\r", with: "")
    }
}

