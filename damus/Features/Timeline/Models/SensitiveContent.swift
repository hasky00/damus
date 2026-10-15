//
//  SensitiveContent.swift
//  damus
//
//  Detects notes the author marked as sensitive, so their content can be
//  covered until the user chooses to reveal it.
//

import Foundation

/// Why a note's content is covered until the user taps to reveal it.
enum SensitiveContentReason: Equatable {
    /// NIP-36 `content-warning` tag, with the author's optional reason.
    case content_warning(reason: String?)
    /// The note is tagged `#nsfw`.
    case nsfw_hashtag

    /// Localized explanation shown on the cover.
    var explanation: String {
        switch self {
        case .content_warning(let reason?):
            return String(format: NSLocalizedString("Content warning: %@", comment: "Explanation on the sensitive content cover, followed by the reason the author gave"), reason)
        case .content_warning(nil):
            return NSLocalizedString("The author marked this note as sensitive.", comment: "Explanation on the sensitive content cover when the author gave no reason")
        case .nsfw_hashtag:
            return NSLocalizedString("This note is tagged #nsfw.", comment: "Explanation on the sensitive content cover for notes with the #nsfw tag")
        }
    }
}

/// Returns why `ev` should be covered, or nil if it isn't marked sensitive.
///
/// A NIP-36 `["content-warning", "<reason>"]` tag takes precedence over an
/// `#nsfw` hashtag, so the author's own reason is shown when both exist.
///
/// - Parameter ev: The note to check.
/// - Returns: The reason to show on the cover, or nil.
func sensitive_content_reason(ev: NostrEvent) -> SensitiveContentReason? {
    if let tag = ev.tags.first(where: { t in t.count >= 1 && t[0].matches_str("content-warning") }) {
        let reason = tag.count >= 2 ? tag[1].string().trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return .content_warning(reason: reason.isEmpty ? nil : reason)
    }

    if !nsfw_tag_filter(ev: ev) {
        return .nsfw_hashtag
    }

    return nil
}
