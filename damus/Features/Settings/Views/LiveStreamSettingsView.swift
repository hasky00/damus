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

    /// Default ingest URL shown as a placeholder so the user knows the expected shape.
    private let placeholderURL = "rtmp://in.zap.stream/live"

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
        }
        .navigationTitle(NSLocalizedString("Go Live", comment: "Navigation title for the Go Live settings page."))
        .navigationBarTitleDisplayMode(.large)
    }

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
