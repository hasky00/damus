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

    private var notConfigured: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.largeTitle)
            Text("Add your streaming server and key under Settings → Go Live first.", comment: "Shown on the Go Live screen when no RTMP server is configured.")
                .multilineTextAlignment(.center)
            Button(NSLocalizedString("Close", comment: "Button that closes the Go Live screen."), action: close)
        }
        .foregroundColor(.white)
        .padding()
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
