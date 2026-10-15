//
//  LiveBroadcaster.swift
//  damus
//
//  Created by Hasky on 2026-10-15.
//

import AVFoundation
import Foundation
import HaishinKit
import RTMPHaishinKit

/// Captures the front camera and microphone and pushes them to an RTMP server.
///
/// This is the "Go Live" engine. It owns the audio session, the capture
/// mixer and the RTMP session, and exposes a simple state machine for the UI.
/// It also acts as a preview source so a view can show what is being sent.
///
/// All public members run on the main actor so SwiftUI can observe `state`
/// directly. The heavy lifting (capture, encoding, networking) happens inside
/// HaishinKit's own actors and never blocks the main thread.
@MainActor
final class LiveBroadcaster: ObservableObject {
    /// Where the broadcast currently is.
    enum State: Equatable {
        case idle
        case connecting
        case live
        case error(String)

        /// True while a start has been requested and not yet stopped.
        var isActive: Bool {
            switch self {
            case .connecting, .live: return true
            case .idle, .error: return false
            }
        }
    }

    @Published private(set) var state: State = .idle

    /// Audio bitrate in bits per second. 96 kbps AAC is plenty for voice.
    static let audioBitRate = 96_000
    /// Portrait 720p, which is what a phone held upright produces.
    static let videoSize = CGSize(width: 720, height: 1280)
    /// Video bitrate in bits per second. 1.5 Mbps keeps 720p watchable on mobile data.
    static let videoBitRate = 1_500_000

    private let mixer = MediaMixer()
    private var session: (any Session)?
    private var readyStateTask: Task<Void, Never>?

    /// Starts broadcasting camera and microphone to `rtmpURL/streamKey`.
    ///
    /// - Parameters:
    ///   - rtmpURL: Server URL such as `rtmp://in.ca.zap.stream:1935/good`.
    ///   - streamKey: Secret key issued by the streaming provider.
    func start(rtmpURL: String, streamKey: String) async {
        guard !state.isActive else { return }
        guard let url = Self.ingestURL(server: rtmpURL, key: streamKey) else {
            state = .error(NSLocalizedString("The server URL is not a valid rtmp:// address.", comment: "Go Live error shown when the RTMP URL cannot be parsed."))
            return
        }

        state = .connecting
        // Idempotent: tells HaishinKit how to handle rtmp:// URLs.
        await SessionBuilderFactory.shared.register(RTMPSessionFactory())

        guard await Self.requestMicrophonePermission() else {
            state = .error(NSLocalizedString("Microphone access is off. Enable it for Damus in iOS Settings.", comment: "Go Live error shown when microphone permission is denied."))
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            state = .error(NSLocalizedString("Camera access is off. Enable it for Damus in iOS Settings.", comment: "Go Live error shown when camera permission is denied."))
            return
        }

        do {
            try Self.activateAudioSession()
            try await configureVideo()
            try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))

            guard let session = try await SessionBuilderFactory.shared.make(url).setMode(.publish).build() else {
                throw BroadcastError.unsupportedURL
            }
            self.session = session

            var audio = await session.stream.audioSettings
            audio.bitRate = Self.audioBitRate
            try await session.stream.setAudioSettings(audio)

            var video = await session.stream.videoSettings
            video.videoSize = Self.videoSize
            video.bitRate = Self.videoBitRate
            try await session.stream.setVideoSettings(video)

            await mixer.addOutput(session.stream)
            await mixer.startRunning()
            observeReadyState(of: session)

            try await session.connect { [weak self] in
                Task { @MainActor in self?.handleDisconnect() }
            }
        } catch {
            await teardown()
            state = .error(error.localizedDescription)
        }
    }

    /// Shows the camera in the preview without streaming, so the user can
    /// frame themselves before going live. Safe to call before `start`.
    func startPreview() async {
        guard !state.isActive else { return }
        guard await AVCaptureDevice.requestAccess(for: .video) else { return }
        try? await configureVideo()
        await mixer.startRunning()
    }

    /// Stops the broadcast and releases the camera and microphone.
    func stop() async {
        await teardown()
        state = .idle
    }

    // MARK: - Internals

    private enum BroadcastError: LocalizedError {
        case unsupportedURL

        var errorDescription: String? {
            NSLocalizedString("This server URL scheme is not supported. Use an rtmp:// address.", comment: "Go Live error shown when no streaming backend handles the URL.")
        }
    }

    /// Joins the server URL and the stream key into the full RTMP publish URL.
    static func ingestURL(server: String, key: String) -> URL? {
        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedServer.isEmpty, !trimmedKey.isEmpty else { return nil }
        guard let url = URL(string: trimmedServer), let scheme = url.scheme?.lowercased(), scheme == "rtmp" || scheme == "rtmps" else { return nil }
        return url.appendingPathComponent(trimmedKey)
    }

    /// Points the mixer at the front camera in portrait at the chosen size.
    private func configureVideo() async throws {
        await mixer.setSessionPreset(.hd1280x720)
        await mixer.setVideoOrientation(.portrait)
        await Task { @ScreenActor in
            await mixer.screen.size = Self.videoSize
        }.value
        let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        try await mixer.attachVideo(camera) { unit in
            unit.isVideoMirrored = false
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Configures the shared audio session for low-latency voice capture.
    private static func activateAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try audioSession.setActive(true)
    }

    private func observeReadyState(of session: any Session) {
        readyStateTask?.cancel()
        readyStateTask = Task { [weak self] in
            for await ready in await session.readyState {
                guard let self else { return }
                switch ready {
                case .connecting: self.state = .connecting
                case .open: self.state = .live
                case .closing: break
                case .closed:
                    if self.state == .live {
                        self.state = .error(NSLocalizedString("The stream was disconnected.", comment: "Go Live error shown when the server dropped the connection."))
                    }
                }
            }
        }
    }

    private func handleDisconnect() {
        guard state.isActive else { return }
        Task { await teardown() }
        state = .error(NSLocalizedString("Lost connection to the streaming server.", comment: "Go Live error shown after retries to the RTMP server failed."))
    }

    private func teardown() async {
        readyStateTask?.cancel()
        readyStateTask = nil
        if let session {
            try? await session.close()
        }
        session = nil
        await mixer.stopRunning()
        try? await mixer.attachAudio(nil)
        try? await mixer.attachVideo(nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension LiveBroadcaster: MTHKViewRepresentable.PreviewSource {
    /// Feeds the camera picture into a preview view.
    nonisolated func connect(to view: MTHKView) {
        Task { await mixer.addOutput(view) }
    }
}
