//
//  BlackEye.swift
//  damus
//
//  Damus Labs: one-tap knockout for spam and bot accounts.
//

import Foundation
import UIKit

/// Black Eye: one gesture that hits a bad actor where it hurts.
///
/// A punch does three things at once:
/// 1. Blocks the author on this device immediately (via ``BotShield``), so the note
///    and everything else from them vanishes without waiting for a relay round-trip.
/// 2. Adds the author to the user's public mute list (kind 10000), so the block
///    follows them to every Damus install and every client that honours mute lists.
/// 3. Publishes a NIP-56 report (kind 1984) for the note, which is what relay
///    operators and other clients use to decide who to drop.
enum BlackEye {
    /// Throws the punch. Steps 2 and 3 need a private key; step 1 always runs.
    @MainActor
    static func punch(event: NostrEvent, damus_state: DamusState, type: ReportType = .spam) async {
        let target = event.pubkey
        guard target != damus_state.pubkey else { return }

        BotShield.block(target)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        guard let keypair = damus_state.keypair.to_full() else { return }
        let postbox = damus_state.nostrNetwork.postbox

        if !damus_state.mutelist_manager.is_muted(.user(target, nil)),
           let mutelist = toggle_from_mutelist(keypair: keypair,
                                               prev: damus_state.mutelist_manager.event,
                                               to_toggle: .user(target, nil)) {
            damus_state.mutelist_manager.set_mutelist(mutelist)
            await postbox.send(mutelist)
        }

        // NIP-56: impersonation is a profile report, so it goes on the "p" tag;
        // everything else reports the note and names the author alongside it.
        let tags: [[String]]
        if type == .impersonation {
            tags = [["p", target.hex(), type.rawValue]]
        } else {
            tags = [["e", event.id.hex(), type.rawValue], ["p", target.hex()]]
        }
        if let report = NostrEvent(content: "", keypair: keypair.to_keypair(), kind: 1984, tags: tags) {
            await postbox.send(report)
        }
    }
}
