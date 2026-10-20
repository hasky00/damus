//
//  TextHighlight.swift
//  damus
//
//  Text highlights: spans of a note's own text that its author painted yellow or pink
//  while writing it. A highlight travels with the note as an `hl` tag:
//
//      ["hl", "<color>", "<exact text>"]
//
//  Clients that don't know the tag just show the plain note, so nothing is lost.
//

import SwiftUI
import UIKit

/// The colours a span of text can be painted in the composer.
enum TextHighlightColor: String, CaseIterable, Identifiable {
    case yellow
    case pink

    var id: String { rawValue }

    /// Fill used behind the text, in the composer and on rendered notes.
    var fill: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.90, blue: 0.30).opacity(0.65)
        case .pink: return Color(red: 1.0, green: 0.45, blue: 0.75).opacity(0.55)
        }
    }

    var uiFill: UIColor { UIColor(fill) }

    var label: String {
        switch self {
        case .yellow: return NSLocalizedString("Yellow", comment: "Highlight colour name")
        case .pink: return NSLocalizedString("Pink", comment: "Highlight colour name")
        }
    }
}

/// One painted span, as it is stored on the note.
struct TextHighlight: Equatable {
    static let tagName = "hl"
    /// Hard cap so a malicious note can't make rendering crawl.
    static let maxPerNote = 20

    let color: TextHighlightColor
    let text: String

    var tag: [String] { [Self.tagName, color.rawValue, text] }

    /// Highlights carried by a note's tags, in tag order.
    static func from(event: NostrEvent) -> [TextHighlight] {
        var found: [TextHighlight] = []
        for tag in event.tags {
            var i = tag.makeIterator()
            guard tag.count >= 3,
                  let t0 = i.next(), t0.string() == tagName,
                  let t1 = i.next(), let color = TextHighlightColor(rawValue: t1.string()),
                  let t2 = i.next() else { continue }
            let text = t2.string()
            guard !text.isEmpty else { continue }
            found.append(TextHighlight(color: color, text: text))
            if found.count >= maxPerNote { break }
        }
        return found
    }

    /// Paints each highlight's text wherever it occurs in `attributed`.
    static func apply(_ highlights: [TextHighlight], to attributed: inout AttributedString) {
        for highlight in highlights {
            var searchStart = attributed.startIndex
            while let range = attributed[searchStart...].range(of: highlight.text) {
                attributed[range].backgroundColor = highlight.color.fill
                searchStart = range.upperBound
            }
        }
    }
}

extension NSAttributedString.Key {
    /// Composer-side marker: the value is a `TextHighlightColor` raw value.
    static let damusHighlight = NSAttributedString.Key("damusHighlight")
}

extension NSMutableAttributedString {
    /// Paints `range` in the composer with `color`.
    func addTextHighlight(_ color: TextHighlightColor, in range: NSRange) {
        guard range.length > 0, range.upperBound <= length else { return }
        addAttributes([.damusHighlight: color.rawValue, .backgroundColor: color.uiFill], range: range)
    }

    /// Clears any highlight in `range`.
    func removeTextHighlight(in range: NSRange) {
        guard range.length > 0, range.upperBound <= length else { return }
        removeAttribute(.damusHighlight, range: range)
        removeAttribute(.backgroundColor, range: range)
    }
}

extension NSAttributedString {
    /// The painted spans in composer text, as tags ready to attach to the note.
    /// Adjacent runs of the same colour are merged; spans are deduplicated.
    func textHighlights() -> [TextHighlight] {
        var result: [TextHighlight] = []
        var current: (color: TextHighlightColor, text: String)? = nil

        func flush() {
            if let c = current {
                let trimmed = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let hl = TextHighlight(color: c.color, text: trimmed)
                    if !result.contains(hl) { result.append(hl) }
                }
            }
            current = nil
        }

        enumerateAttribute(.damusHighlight, in: NSRange(location: 0, length: length), options: []) { value, range, _ in
            let piece = attributedSubstring(from: range).string
            if let raw = value as? String, let color = TextHighlightColor(rawValue: raw) {
                if let c = current, c.color == color {
                    current = (color, c.text + piece)
                } else {
                    flush()
                    current = (color, piece)
                }
            } else {
                flush()
            }
        }
        flush()
        return Array(result.prefix(TextHighlight.maxPerNote))
    }
}
