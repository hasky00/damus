//
//  DamusLabsExpirements.swift
//  damus
//
//  Created by eric on 10/24/25.
//

import SwiftUI

struct DamusLabsExperiments: View {
    
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore
    @State var show_favorites_explainer: Bool = false
    @State var show_gifs_explainer: Bool = false
    @State var show_halloween_explainer: Bool = false
    @State var show_price_cards_explainer: Bool = false
    @State var show_text_highlights_explainer: Bool = false
    @State var show_bot_shield_explainer: Bool = false
    @State var show_black_eye_explainer: Bool = false
    @State var show_fact_check_explainer: Bool = false
    @State var bot_shield_blocked: Int = BotShield.blocked_count
    
    let favorites_label = NSLocalizedString("Favorites", comment: "Label for a toggle that enables an experimental feature")
    let gifs_label = NSLocalizedString("GIFs", comment: "Label for a toggle that enables an experimental feature")
    let halloween_label = NSLocalizedString("Halloween profile", comment: "Label for a toggle that enables an experimental feature")
    let price_cards_label = NSLocalizedString("Price Cards", comment: "Label for a toggle that enables an experimental feature")
    let text_highlights_label = NSLocalizedString("Text Highlights", comment: "Label for a toggle that enables an experimental feature")
    let bot_shield_label = NSLocalizedString("Bot Shield", comment: "Label for a toggle that enables an experimental feature")
    let black_eye_label = NSLocalizedString("Black Eye", comment: "Label for a toggle that enables an experimental feature")
    let fact_check_label = NSLocalizedString("Fact Check", comment: "Label for a toggle that enables an experimental feature")
    
    var body: some View {
        ScrollView {
            
            LabsLogoView()
            
            VStack(alignment: .leading, spacing: 30) {
                PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("As a subscriber, you’re getting an early look at new and innovative tools. These are beta features — still being tested and tuned. Try them out, share your thoughts, and help us perfect what’s next.", comment: "Damus Labs explainer"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                
                HStack {
                    Spacer()
                    Text("More features coming soon!", comment: "Label indicating that more features for Damus Lab experiments are coming soon.")
                        .font(.title2)
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .padding(.bottom, 2)
                    Spacer()
                }
                .padding(15)
                .background(DamusColors.black)
                .cornerRadius(15)
                .padding(.top, 10)
                
                LabsToggleView(toggleName: favorites_label, systemImage: "heart.fill", isOn: $settings.enable_favourites_feature, showInfo: $show_favorites_explainer)
                LabsToggleView(toggleName: gifs_label, systemImage: "smiley", isOn: $settings.enable_gifs_feature, showInfo: $show_gifs_explainer)
                LabsToggleView(toggleName: halloween_label, systemImage: "moon.stars.fill", isOn: $settings.enable_halloween_profile, showInfo: $show_halloween_explainer)
                LabsToggleView(toggleName: price_cards_label, systemImage: "chart.line.uptrend.xyaxis", isOn: $settings.enable_price_cards_feature, showInfo: $show_price_cards_explainer)
                LabsToggleView(toggleName: text_highlights_label, systemImage: "highlighter", isOn: $settings.enable_text_highlights, showInfo: $show_text_highlights_explainer)
                LabsToggleView(toggleName: bot_shield_label, systemImage: "shield.lefthalf.filled", isOn: $settings.enable_bot_shield, showInfo: $show_bot_shield_explainer)
                if settings.enable_bot_shield {
                    HStack {
                        Text(String(format: NSLocalizedString("%d accounts blocked", comment: "Number of accounts the Bot Shield has blocked"), bot_shield_blocked))
                            .foregroundColor(.gray)
                        Spacer()
                        Button(NSLocalizedString("Reset", comment: "Button that clears the Bot Shield block list")) {
                            BotShield.reset()
                            bot_shield_blocked = BotShield.blocked_count
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 10)
                    .onAppear { bot_shield_blocked = BotShield.blocked_count }
                }
                LabsToggleView(toggleName: black_eye_label, systemImage: "hand.raised.fill", isOn: $settings.enable_black_eye, showInfo: $show_black_eye_explainer)
                LabsToggleView(toggleName: fact_check_label, systemImage: "pawprint.fill", isOn: $settings.enable_fact_check, showInfo: $show_fact_check_explainer)

            }
            .padding([.trailing, .leading], 20)
            .padding(.bottom, 50)
            
            Image("damooseLabs")
                .resizable()
                .accessibilityHidden(true)
                .aspectRatio(contentMode: .fill)
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $show_favorites_explainer) {
            LabsExplainerView(
                labName: favorites_label,
                systemImage: "heart.fill",
                labDescription: NSLocalizedString("This will allow you to pick users to be part of your favorites list. You can also switch your profile timeline to only see posts from your favorite contacts.", comment: "Damus Labs feature explanation"))
        }
        .sheet(isPresented: $show_gifs_explainer) {
            LabsExplainerView(
                labName: gifs_label,
                systemImage: "",
                labDescription: NSLocalizedString("This will allow you to easily add GIFs to your posts. You will see the GIF icon in the attachment bar when creating a post. Tapping it will show featured GIFs for Purple subscribers, and you can also search for GIFs.", comment: "Damus Labs feature explanation"))
        }
        .sheet(isPresented: $show_halloween_explainer) {
            LabsExplainerView(
                labName: halloween_label,
                systemImage: "moon.stars.fill",
                labDescription: NSLocalizedString("Decorates profile pages with a pulsing orange and purple ring around the profile picture and bats and pumpkins drifting over the banner. This is a local theme only you see, and it is never shown on the timeline or on notes. If Reduce Motion is on, the ring stays still and the drifting is skipped.", comment: "Damus Labs feature explanation"))
        }
        .sheet(isPresented: $show_text_highlights_explainer) {
            LabsExplainerView(
                labName: text_highlights_label,
                systemImage: "highlighter",
                labDescription: NSLocalizedString("Adds a highlighter to the composer: select some of your text and paint it yellow or pink. Highlights are stored as an extra tag on the note, so other clients still show the plain text. Notes from others carrying highlights are painted too.", comment: "Damus Labs feature explanation"))
        }
        .sheet(isPresented: $show_fact_check_explainer) {
            LabsExplainerView(
                labName: fact_check_label,
                systemImage: "pawprint.fill",
                labDescription: NSLocalizedString("Adds a Fact check option to the note menu. Give a note a verdict (checks out, needs context, doesn't hold up, satire), add a source, and it is published as a public label any client can read. Under each note you see the verdicts from people you follow, and can reveal the rest. Sniff, the Hasky Labs fact-checking agent, can be asked to look into a note too, but only when you ask.", comment: "Damus Labs feature explanation"))
        }
        .sheet(isPresented: $show_black_eye_explainer) {
            LabsExplainerView(
                labName: black_eye_label,
                systemImage: "hand.raised.fill",
                labDescription: NSLocalizedString("Adds a Black Eye option to the note menu. One tap blocks the author on this device, adds them to your public mute list so the block follows you to every client, and publishes a report for the note so relay operators and other clients can drop them too. Pick Spam bot, Porn bot or Impersonator to say why.", comment: "Damus Labs feature explanation"))
        }
        .sheet(isPresented: $show_bot_shield_explainer) {
            LabsExplainerView(
                labName: bot_shield_label,
                systemImage: "shield.lefthalf.filled",
                labDescription: NSLocalizedString("Hides notes that contain adult-content keywords, #nsfw or similar hashtags, or a content warning, and from accounts whose profile name, bio or picture reads like a porn bot. Any account that trips the shield is blocked on this device, so nothing else from it is shown. The block list stays on your phone and is never published. Tap Reset to clear it.", comment: "Damus Labs feature explanation"))
        }
        .sheet(isPresented: $show_price_cards_explainer) {
            LabsExplainerView(
                labName: price_cards_label,
                systemImage: "chart.line.uptrend.xyaxis",
                labDescription: NSLocalizedString("This will show a small price card, with the current price, 24h change and a sparkline, under notes that mention a ticker like $BTC. Prices are fetched from Coinbase, a third-party service, which will see the tickers you view and your IP address. Up to 3 cards are shown per note.", comment: "Damus Labs feature explanation"))
        }
    }
}

#Preview {
    PurpleBackdrop {
        DamusLabsExperiments(damus_state: test_damus_state, settings: test_damus_state.settings)
    }
}
