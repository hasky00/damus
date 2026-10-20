//
//  LiveBroadcastView.swift
//  damus
//
//  Created by Hasky on 2026-10-15.
//

import HaishinKit
import SwiftUI

/// Full-screen "Go Live" screen: camera preview, a title, and one big button.
///
/// Going live does two things in order: tells zap.stream the title to put on
/// the live event it publishes, then starts pushing camera and microphone to
/// the ingest server from settings. Ending the stream stops the push;
/// zap.stream marks the event as ended on its own when the ingest drops.
struct LiveBroadcastView: View {
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore
    @StateObject private var broadcaster = LiveBroadcaster()
    @State private var title: String = ""
    @State private var titleError: String? = nil
    @State private var startedAt: Date? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if settings.live_broadcast_configured {
                preview
                overlay
            } else {
                notConfigured
            }
        }
        .task {
            if settings.live_broadcast_configured {
                await broadcaster.startPreview()
            }
        }
        .onChange(of: settings.live_broadcast_configured) { configured in
            if configured {
                Task { await broadcaster.startPreview() }
            }
        }
        .onDisappear {
            Task { await broadcaster.stop() }
        }
    }

    // MARK: - Pieces

    private var preview: some View {
        MTHKViewRepresentable(previewSource: broadcaster, videoGravity: .resizeAspectFill)
            .ignoresSafeArea()
    }

    private var overlay: some View {
        VStack {
            topBar
            Spacer()
            if let error = currentError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            if broadcaster.state.isActive {
                endButton
            } else {
                titleField
                goLiveButton
            }
        }
        .padding(.bottom, 24)
    }

    private var topBar: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            Spacer()
            if broadcaster.state == .live {
                LiveBadge(since: startedAt)
            } else if broadcaster.state == .connecting {
                ProgressView().tint(.white)
            }
        }
        .padding()
    }

    private var titleField: some View {
        TextField(NSLocalizedString("What are you streaming?", comment: "Placeholder for the live stream title field."), text: $title)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)
            .padding(.horizontal)
    }

    private var goLiveButton: some View {
        Button(action: goLive) {
            Label(NSLocalizedString("Go Live", comment: "Button that starts a live stream."), systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(14)
        }
        .disabled(broadcaster.state == .connecting)
        .padding(.horizontal)
    }

    private var endButton: some View {
        Button(action: endStream) {
            Text("End stream", comment: "Button that stops a live stream.")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.9))
                .foregroundColor(.red)
                .cornerRadius(14)
        }
        .padding(.horizontal)
    }

    /// First-run guide: what you need to stream, and where to paste it.
    /// The fields write straight into settings, so the moment both are filled the
    /// preview appears without leaving this screen.
    private var notConfigured: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(8)
                    }
                }

                Image(systemName: "video.fill")
                    .font(.largeTitle)
                    .frame(maxWidth: .infinity)

                Text("Go live from Damus", comment: "Title of the Go Live setup guide.")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)

                Text("Your stream goes through zap.stream, so anyone on Nostr can watch, chat and zap. It takes one minute to set up.", comment: "Intro text of the Go Live setup guide.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                setupStep(1, NSLocalizedString("Open zap.stream and sign in with your Nostr key.", comment: "Go Live setup guide, step 1."))
                setupStep(2, NSLocalizedString("Go to Dashboard → Stream settings and copy the Server URL and Stream key.", comment: "Go Live setup guide, step 2."))
                setupStep(3, NSLocalizedString("Paste them here. Both are kept in your keychain.", comment: "Go Live setup guide, step 3."))

                VStack(spacing: 10) {
                    TextField("rtmp://in.zap.stream:1935/good", text: $settings.live_rtmp_url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                    SecureField(NSLocalizedString("Stream key", comment: "Prompt for the secret stream key in the Go Live setup guide."), text: $settings.live_stream_key)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                }
                .textFieldStyle(.roundedBorder)
                .foregroundColor(.black)

                Link(destination: URL(string: "https://zap.stream/dashboard")!) {
                    Text("Open zap.stream", comment: "Button in the Go Live setup guide that opens zap.stream in the browser.")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DamusColors.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Text("Once you tap Go Live, your stream shows up on zap.stream and in Nostr clients that support live streams.", comment: "Closing note of the Go Live setup guide.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .foregroundColor(.white)
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(DamusColors.purple)
                .foregroundColor(.white)
                .clipShape(Circle())
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The most relevant error to show: a title-update failure first, then the broadcaster's.
    private var currentError: String? {
        if let titleError { return titleError }
        if case .error(let message) = broadcaster.state { return message }
        return nil
    }

    // MARK: - Actions

    private func goLive() {
        titleError = nil
        Task {
            await sendTitle()
            await broadcaster.start(rtmpURL: settings.live_rtmp_url, streamKey: settings.live_stream_key)
            if broadcaster.state == .live {
                startedAt = Date()
            }
        }
    }

    /// Tells zap.stream the title before the ingest starts, so the live event carries it.
    /// A failure here is shown but does not block going live.
    private func sendTitle() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let apiBase = ZapStreamClient.apiBase(forIngest: settings.live_rtmp_url) else {
            titleError = ZapStreamClient.ClientError.notZapStream.localizedDescription
            return
        }
        do {
            try await ZapStreamClient(apiBase: apiBase, keypair: damus_state.keypair).updateStreamDetails(title: trimmed, summary: nil)
        } catch {
            titleError = error.localizedDescription
        }
    }

    private func endStream() {
        Task {
            await broadcaster.stop()
            startedAt = nil
        }
    }

    private func close() {
        Task {
            await broadcaster.stop()
            dismiss()
        }
    }
}

/// Red "LIVE" pill with a running clock.
private struct LiveBadge: View {
    let since: Date?

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Circle().fill(Color.white).frame(width: 8, height: 8)
                Text("LIVE", comment: "Badge shown while streaming.")
                    .fontWeight(.bold)
                if let since {
                    Text(elapsed(from: since, to: context.date))
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.red)
            .clipShape(Capsule())
        }
    }

    private func elapsed(from start: Date, to now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(start))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
