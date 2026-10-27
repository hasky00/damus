//
//  ContentFilters.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-09-18.
//

import Foundation

/// Timeline source determines whether to show content from follows or favorites
enum TimelineSource: CustomStringConvertible {
    case follows
    case favorites

    var description: String {
        switch self {
        case .follows:
            return NSLocalizedString("Follows", comment: "Show Notes from your following")
        case .favorites:
            return NSLocalizedString("Favorites", comment: "Show Notes from your favorites")
        }
    }
}

/// Simple filter to determine whether to show posts or all posts and replies.
enum FilterState : Int {
    case posts = 0
    case posts_and_replies = 1
    case conversations = 2
    case follow_list = 3
    case live = 4
    case live_chat = 5

    func filter(ev: NostrEvent) -> Bool {
        switch self {
        case .posts:
            return ev.known_kind == .boost || ev.known_kind == .highlight || !ev.is_reply()
        case .posts_and_replies:
            return true
        case .conversations:
            return true
        case .follow_list:
            return ev.known_kind == .follow_list
        case .live:
            return ev.known_kind == .live
        case .live_chat:
            return ev.known_kind == .live_chat
        }
    }
}

extension FilterState {
    /// The labelled options the home timeline's filter selector offers.
    ///
    /// Shared by the top ``CustomPicker`` and the tab view's bottom accessory —
    /// only one of the two is on screen at a time, but they must offer the same
    /// options in the same order, so the labels live in one place.
    static var timeline_filter_options: [(String, FilterState)] {
        [
            (NSLocalizedString("Notes", comment: "Label for filter for seeing only notes (instead of notes and replies)."), .posts),
            (NSLocalizedString("Notes & Replies", comment: "Label for filter for seeing notes and replies (instead of only notes)."), .posts_and_replies),
        ]
    }
}

/// Simple filter to determine whether to show posts with #nsfw tags
func nsfw_tag_filter(ev: NostrEvent) -> Bool {
    return ev.referenced_hashtags.first(where: { t in t.hashtag.caseInsensitiveCompare("nsfw") == .orderedSame }) == nil
}

/// Filter to hide posts with too many hashtags (spam detection)
/// Checks both the event's "t" tags and hashtags in content text.
/// If either exceeds the threshold, the post is filtered.
func hashtag_spam_filter(ev: NostrEvent, max_hashtags: Int) -> Bool {
    // Check "t" tags count
    var tag_count = 0
    for _ in ev.referenced_hashtags {
        tag_count += 1
        if tag_count > max_hashtags {
            return false
        }
    }

    return true
}

@MainActor
func get_repost_of_muted_user_filter(damus_state: DamusState) -> ((_ ev: NostrEvent) -> Bool) {
    return { ev in
        guard ev.known_kind == .boost else { return true }
        // This needs to use cached because it can be way too slow otherwise
        guard let inner_ev = ev.get_cached_inner_event(cache: damus_state.events) else { return true }
        return should_show_event(state: damus_state, ev: inner_ev)
    }
}

func timestamp_filter(ev: NostrEvent) -> Bool {
    // Allow notes that are created no more than 3 seconds in the future
    // to account for natural clock skew between sender and receiver.
    ev.age >= -3
}

/// Generic filter with various tweakable settings
struct ContentFilters {
    var filters: [(NostrEvent) -> Bool]

    func filter(ev: NostrEvent) -> Bool {
        for filter in filters {
            if !filter(ev) {
                return false
            }
        }

        return true
    }
}

extension ContentFilters {
    @MainActor
    static func default_filters(damus_state: DamusState) -> ContentFilters {
        return ContentFilters(filters: ContentFilters.defaults(damus_state: damus_state))
    }

    /// Returns the app's standard content filters.
    ///
    /// The logged-in user's own events bypass NSFW, profanity and hashtag-spam filters so they remain visible on their own profile.
    @MainActor
    static func defaults(damus_state: DamusState) -> [(NostrEvent) -> Bool] {
        var filters = Array<(NostrEvent) -> Bool>()
        if damus_state.settings.enable_bot_shield {
            filters.append { ev in
                BotShield.should_show(ev: ev, damus_state: damus_state)
            }
        }
        if damus_state.settings.hide_nsfw_tagged_content {
            filters.append { ev in
                guard ev.pubkey != damus_state.pubkey else { return true }
                return nsfw_tag_filter(ev: ev)
            }
        }
        if damus_state.settings.profanity_filter_mode == .hide {
            filters.append { ev in
                guard ev.pubkey != damus_state.pubkey else { return true }
                return profanity_filter(ev: ev)
            }
        }
        if damus_state.settings.hide_hashtag_spam {
            let max_hashtags = damus_state.settings.max_hashtags
            filters.append { ev in
                guard ev.pubkey != damus_state.pubkey else { return true }
                return hashtag_spam_filter(ev: ev, max_hashtags: max_hashtags)
            }
        }
        filters.append(get_repost_of_muted_user_filter(damus_state: damus_state))
        filters.append(timestamp_filter)
        return filters
    }
}

// MARK: - Bot Shield (Damus Labs)
import Foundation

/// Blocks porn bots and adult-content spam.
///
/// A note trips the shield when its text, hashtags, content warning, or the
/// author's profile (name, bio, picture URL) contains adult keywords.
/// The author's pubkey is then stored locally, and everything they post is
/// hidden from that point on. Nothing is published to relays.
enum BotShield {
    private static let defaults_key = "labs_bot_shield_blocked_pubkeys"

    /// Phrases matched as plain substrings (case-insensitive).
    static let phrases: [String] = [
        "porn", "pornhub", "onlyfans", "only fans", "fansly", "xxx", "hentai",
        "nudes", "nude pic", "sex cam", "sexcam", "camgirl", "cam girl", "webcam show",
        "escort", "sexting", "sext me", "dick pic", "blowjob", "blow job", "handjob",
        "gangbang", "milf", "hardcore sex", "sex video", "sex tape", "adult content",
        "adult video", "18+ only", "horny", "fuck me", "cumshot", "deepthroat",
        "snap premium", "snapchat premium", "my of link", "link in bio for nudes",
        "nsfw", "lewd", "boobs", "big tits", "pussy pics", "sugar daddy", "sugar baby",
    ]

    /// Words matched only as whole words, since they appear inside innocent words.
    static let exact_words: [String] = [
        "anal", "nude", "tits", "cum", "bdsm", "threesome", "orgy",
    ]

    private static let word_regex: NSRegularExpression = {
        let alternation = exact_words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try! NSRegularExpression(pattern: "\\b(\(alternation))s?\\b", options: [.caseInsensitive])
    }()

    private static var blocked: Set<Pubkey> = load()

    /// Number of accounts the shield has blocked so far.
    static var blocked_count: Int { blocked.count }

    /// Clears every account the shield has blocked.
    static func reset() {
        blocked = []
        UserDefaults.standard.removeObject(forKey: defaults_key)
    }

    static func is_blocked(_ pubkey: Pubkey) -> Bool {
        return blocked.contains(pubkey)
    }

    static func block(_ pubkey: Pubkey) {
        guard !blocked.contains(pubkey) else { return }
        blocked.insert(pubkey)
        save()
    }

    /// Whether this text reads like adult-content spam.
    static func is_adult_text(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let lowered = text.lowercased()
        for phrase in phrases where lowered.contains(phrase) {
            return true
        }
        let range = NSRange(lowered.startIndex..., in: lowered)
        return word_regex.firstMatch(in: lowered, range: range) != nil
    }

    /// Whether this note, on its own, trips the shield.
    static func is_adult_event(_ ev: NostrEvent) -> Bool {
        if is_adult_text(ev.content) {
            return true
        }
        for tag in ev.referenced_hashtags where is_adult_text(tag.hashtag) {
            return true
        }
        if let warning = ev.tags.first(where: { $0.count >= 1 && $0[0].matches_str("content-warning") }) {
            // A content warning with no reason is treated as adult content.
            if warning.count < 2 { return true }
            if is_adult_text(warning[1].string()) { return true }
        }
        return false
    }

    /// Whether the author's profile reads like a porn bot.
    static func is_adult_profile(_ profile: Profile?) -> Bool {
        guard let profile else { return false }
        if let name = profile.name, is_adult_text(name) { return true }
        if let display_name = profile.display_name, is_adult_text(display_name) { return true }
        if let about = profile.about, is_adult_text(about) { return true }
        if let website = profile.website, is_adult_text(website) { return true }
        if let picture = profile.picture, is_adult_text(picture) { return true }
        return false
    }

    /// Returns `false` when `ev` should be hidden. Blocks the author on a hit.
    ///
    /// The logged-in user is never shielded.
    @MainActor
    static func should_show(ev: NostrEvent, damus_state: DamusState) -> Bool {
        guard damus_state.settings.enable_bot_shield else { return true }
        guard ev.pubkey != damus_state.pubkey else { return true }

        if is_blocked(ev.pubkey) {
            return false
        }

        let profile = try? damus_state.profiles.lookup(id: ev.pubkey)
        if is_adult_event(ev) || is_adult_profile(profile) {
            block(ev.pubkey)
            return false
        }

        return true
    }

    private static func load() -> Set<Pubkey> {
        guard let hexes = UserDefaults.standard.stringArray(forKey: defaults_key) else { return [] }
        return Set(hexes.compactMap { Pubkey(hex: $0) })
    }

    private static func save() {
        UserDefaults.standard.set(blocked.map { $0.hex() }, forKey: defaults_key)
    }
}
