//
//  LiveStreamSettingsView.swift
//  damus
//
//  Created by Hasky on 2026-10-15.
//

import SwiftUI

/// Settings page for the "Go Live" feature.
///
/// Lets the user store the RTMP ingest URL and stream key of their streaming
/// provider (zap.stream by default). Both values are kept in the keychain via
/// `UserSettingsStore`; nothing is sent anywhere from this screen.
struct LiveStreamSettingsView: View {
    @ObservedObject var settings: UserSettingsStore
#if canImport(HaishinKit)
    // The broadcaster needs the streaming library, which only the app target
    // links; the share/highlighter extensions compile this view without it.
    @StateObject private var broadcaster = LiveBroadcaster()
#endif

    /// Default ingest URL shown as a placeholder so the user knows the expected shape.
    private let placeholderURL = "rtmp://in.zap.stream:1935/good"

    var body: some View {
        Form {
            Section(
                header: Text("Streaming server", comment: "Section title for the RTMP server used when going live."),
                footer: Text("Get these from your zap.stream stream settings. The key lets anyone broadcast on your channel, so keep it private.", comment: "Explanation under the Go Live server fields.")
            ) {
                TextField(placeholderURL, text: $settings.live_rtmp_url)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)

                SecureField(NSLocalizedString("Stream key", comment: "Prompt for the secret stream key used when going live."), text: $settings.live_stream_key)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
            }

            Section {
                statusRow
            }

#if canImport(HaishinKit)
            if settings.live_broadcast_configured {
                Section(
                    header: Text("Test broadcast", comment: "Section title for the microphone test controls on the Go Live settings page."),
                    footer: Text("Sends your microphone to the server above so you can check it works. Nothing is announced on Nostr.", comment: "Explanation under the Go Live test controls.")
                ) {
                    broadcastRow
                }
            }
#endif
        }
        .navigationTitle(NSLocalizedString("Go Live", comment: "Navigation title for the Go Live settings page."))
        .navigationBarTitleDisplayMode(.large)
    }

#if canImport(HaishinKit)
    /// Start/Stop button plus the broadcaster's current state.
    private var broadcastRow: some View {
        HStack {
            Button(action: toggleBroadcast) {
                Text(broadcaster.state.isActive
                     ? NSLocalizedString("Stop", comment: "Button that stops the Go Live test broadcast.")
                     : NSLocalizedString("Start microphone test", comment: "Button that starts the Go Live test broadcast."))
            }
            .disabled(broadcaster.state == .connecting)
            Spacer()
            broadcastStateLabel
        }
        .onDisappear {
            Task { await broadcaster.stop() }
        }
    }

    /// Human-readable broadcaster state, coloured so "live" stands out.
    @ViewBuilder
    private var broadcastStateLabel: some View {
        switch broadcaster.state {
        case .idle:
            EmptyView()
        case .connecting:
            ProgressView()
        case .live:
            Label(NSLocalizedString("On air", comment: "Status shown while the Go Live test broadcast is running."), systemImage: "dot.radiowaves.left.and.right")
                .foregroundColor(.red)
        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .multilineTextAlignment(.trailing)
        }
    }

    private func toggleBroadcast() {
        Task {
            if broadcaster.state.isActive {
                await broadcaster.stop()
            } else {
                await broadcaster.start(rtmpURL: settings.live_rtmp_url, streamKey: settings.live_stream_key)
            }
        }
    }

#endif

    /// One-line summary telling the user whether the device is ready to broadcast.
    private var statusRow: some View {
        HStack {
            Image(systemName: settings.live_broadcast_configured ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(settings.live_broadcast_configured ? .green : .secondary)
            Text(settings.live_broadcast_configured
                 ? NSLocalizedString("Ready to go live", comment: "Status shown when the Go Live server and key are both set.")
                 : NSLocalizedString("Enter a server URL and stream key", comment: "Status shown when Go Live is not yet configured."))
                .foregroundColor(.secondary)
        }
    }
}

struct LiveStreamSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        LiveStreamSettingsView(settings: UserSettingsStore())
    }
}
