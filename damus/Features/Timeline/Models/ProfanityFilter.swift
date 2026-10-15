//
//  ProfanityFilter.swift
//  damus
//
//  On-device profanity detection and masking for note text.
//

import Foundation

/// How the app treats notes that contain profanity.
enum ProfanityFilterMode: String, CaseIterable, Identifiable, StringCodable, Equatable {
    /// Show notes unchanged.
    case off
    /// Replace profane words with asterisks, keeping the first letter (e.g. `f***`).
    case mask
    /// Remove notes containing profanity from timelines.
    case hide

    var id: String { rawValue }

    init?(from string: String) {
        guard let mode = ProfanityFilterMode(rawValue: string) else { return nil }
        self = mode
    }

    func to_string() -> String {
        return rawValue
    }

    /// Localized label for the settings picker.
    func text_description() -> String {
        switch self {
        case .off:
            return NSLocalizedString("Off", comment: "Profanity filter setting option: do not filter profanity")
        case .mask:
            return NSLocalizedString("Mask words", comment: "Profanity filter setting option: replace profane words with asterisks")
        case .hide:
            return NSLocalizedString("Hide notes", comment: "Profanity filter setting option: hide notes that contain profanity")
        }
    }
}

/// Detects and masks profane words using a small built-in English word list.
///
/// Matching is whole-word and case-insensitive, so innocent words that merely
/// contain a profane substring (e.g. "assistant", "class", "Scunthorpe") are
/// left alone. Users can block anything else with mute words.
enum ProfanityFilter {
    /// Roots that also match when a suffix follows, e.g. "fuck" → "fucking".
    /// Only roots that don't start common innocent words belong here.
    static let stems = [
        "fuck", "motherfuck", "shit", "bullshit", "bitch", "cunt",
        "asshole", "piss", "wank", "twat", "faggot", "nigger", "nigga",
    ]

    /// Words matched exactly, optionally plural (`s`/`es`), e.g. "ass" but not "assume".
    static let exact_words = [
        "ass", "arse", "dick", "cock", "pussy", "slut", "whore",
        "bastard", "prick", "fag", "retard", "dickhead", "jackass",
    ]

    /// Combined whole-word pattern for `stems` and `exact_words`.
    private static let regex: NSRegularExpression = {
        let stems = ProfanityFilter.stems.joined(separator: "|")
        let exact = ProfanityFilter.exact_words.joined(separator: "|")
        let pattern = #"\b(?:(?:"# + stems + #")\p{L}*|(?:"# + exact + #")(?:e?s)?)\b"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// Whether `text` contains at least one profane word.
    ///
    /// - Parameter text: Raw note text.
    /// - Returns: `true` if any word in the list matches.
    static func contains_profanity(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// Masks profane words in `text`, keeping each word's first letter.
    ///
    /// - Parameter text: Text to mask.
    /// - Returns: The text with matches replaced, e.g. "what the f***".
    static func mask(_ text: String) -> String {
        var result = text
        let range = NSRange(text.startIndex..., in: text)
        // Replace from the end so earlier ranges stay valid.
        for match in regex.matches(in: text, range: range).reversed() {
            guard let r = Range(match.range, in: result) else { continue }
            result.replaceSubrange(r, with: masked_word(result[r]))
        }
        return result
    }

    /// Masks profane words in an attributed string, keeping links, mentions
    /// and other styling on the surrounding text intact.
    ///
    /// - Parameter attributed: Rendered note text.
    /// - Returns: The attributed string with matches replaced.
    static func mask(_ attributed: AttributedString) -> AttributedString {
        let plain = String(attributed.characters)
        let range = NSRange(plain.startIndex..., in: plain)
        let matches = regex.matches(in: plain, range: range)
        guard !matches.isEmpty else { return attributed }

        var result = attributed
        for match in matches.reversed() {
            guard let r = Range(match.range, in: result) else { continue }
            let word = String(result[r].characters)
            result.characters.replaceSubrange(r, with: masked_word(word))
        }
        return result
    }

    /// Keeps the first character and replaces the rest with `*`.
    private static func masked_word<S: StringProtocol>(_ word: S) -> String {
        guard let first = word.first else { return "" }
        return String(first) + String(repeating: "*", count: word.count - 1)
    }
}

extension CompatibleText {
    /// A copy of this text with profane words masked. Icons are left as-is.
    func masking_profanity() -> CompatibleText {
        let masked_items = items.map { item -> Item in
            guard case .attributed_string(let attributed) = item else { return item }
            return .attributed_string(ProfanityFilter.mask(attributed))
        }
        return CompatibleText(items: masked_items)
    }
}

/// Timeline filter that drops notes containing profanity.
///
/// - Parameter ev: The note to check.
/// - Returns: `false` if the note's content contains profanity.
func profanity_filter(ev: NostrEvent) -> Bool {
    return !ProfanityFilter.contains_profanity(ev.content)
}
