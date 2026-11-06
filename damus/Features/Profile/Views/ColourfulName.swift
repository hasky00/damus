//
//  ColourfulName.swift
//  damus
//
//  Created by Hasky on 11/6/26.
//

import SwiftUI

/// Colours and rules for the Colourful Name experiment (Damus Labs).
///
/// Paints your own display name with a yellow to pink gradient wherever the app
/// shows it. This is a local look only: nothing is published, and other clients
/// keep showing the plain name.
enum ColourfulName {
    /// Warm golden yellow, #FFC700. Deeper than pure yellow so it stays readable in light mode.
    static let yellow = Color(red: 1.0, green: 199.0 / 255.0, blue: 0.0)
    /// Hot pink, #FF2D95.
    static let pink = Color(red: 1.0, green: 45.0 / 255.0, blue: 149.0 / 255.0)

    /// Left to right yellow to pink gradient used to fill the name.
    static let gradient = LinearGradient(
        colors: [yellow, pink],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Whether the name of `pubkey` should be painted: the experiment is on and it is your own account.
    @MainActor
    static func applies(to pubkey: Pubkey, damus: DamusState) -> Bool {
        guard damus.settings.enable_colourful_name else {
            return false
        }

        return pubkey == damus.pubkey
    }
}

extension View {
    /// Fills the view (a name label) with the Colourful Name gradient when `enabled` is true.
    @ViewBuilder
    func colourfulName(_ enabled: Bool) -> some View {
        if enabled {
            self.foregroundStyle(ColourfulName.gradient)
        } else {
            self
        }
    }
}
