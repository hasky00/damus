//
//  VoiceNoteView.swift
//  damus
//
//  Inline player for NIP-A0 voice notes (kinds 1222 and 1244).
//

import AVFoundation
import SwiftUI

/// Plays the audio a voice note points at, with a play/pause button, a
/// scrubbable progress bar and the remaining time.
///
/// The note's content is the audio URL; its optional `imeta` tag may carry a
/// `duration` we can show before playback has loaded anything.
struct VoiceNoteView: View {
    let damus_state: DamusState
    let event: NostrEvent

    @StateObject private var player = VoiceNotePlayer()

    /// The audio URL from the note's content, or nil when the note is malformed.
    private var audioURL: URL? {
        let content = event.get_content(damus_state.keypair).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: content), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    /// Duration advertised in the `imeta` tag, used until the player knows better.
    private var taggedDuration: TimeInterval? {
        for tag in event.tags {
            guard tag.count >= 2, tag[0].matches_str("imeta") else { continue }
            for i in 1..<tag.count {
                let part = tag[i].string()
                guard part.hasPrefix("duration ") else { continue }
                return TimeInterval(part.dropFirst("duration ".count))
            }
        }
        return nil
    }

    var body: some View {
        if let audioURL {
            playerBody(url: audioURL)
        } else {
            Text(NSLocalizedString("Voice note unavailable", comment: "Shown when a voice note has no playable audio URL."))
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func playerBody(url: URL) -> some View {
        HStack(spacing: 12) {
            Button {
                player.toggle(url: url)
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(DamusColors.purple))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying
                                ? NSLocalizedString("Pause voice note", comment: "Accessibility label for pausing a voice note.")
                                : NSLocalizedString("Play voice note", comment: "Accessibility label for playing a voice note."))

            VStack(alignment: .leading, spacing: 6) {
                ProgressBar(progress: player.progress) { fraction in
                    player.seek(to: fraction)
                }
                .frame(height: 6)

                HStack {
                    Image(systemName: "waveform")
                        .font(.caption2)
                    Text(timeLabel)
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DamusColors.neutral1)
        )
        .onDisappear { player.pause() }
    }

    /// Remaining time while playing, otherwise the total length.
    private var timeLabel: String {
        let total = player.duration ?? taggedDuration ?? 0
        let shown = player.isPlaying || player.progress > 0 ? max(0, total - player.currentTime) : total
        let secs = Int(shown.rounded())
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}

/// A thin tappable progress bar; dragging across it seeks.
private struct ProgressBar: View {
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(DamusColors.purple)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        onSeek(max(0, min(1, value.location.x / geo.size.width)))
                    }
            )
        }
    }
}

/// Small AVPlayer wrapper that publishes progress for one voice note at a time.
@MainActor
final class VoiceNotePlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    deinit {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    /// Plays or pauses; creates the player lazily on first play.
    func toggle(url: URL) {
        if isPlaying {
            pause()
            return
        }
        if player == nil { setUp(url: url) }
        play()
    }

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Jumps to `fraction` (0...1) of the track.
    func seek(to fraction: Double) {
        guard let player, let duration, duration > 0 else { return }
        let target = CMTime(seconds: fraction * duration, preferredTimescale: 600)
        player.seek(to: target)
        currentTime = fraction * duration
        progress = fraction
    }

    private func setUp(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.update(time: time, item: item) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finished() }
        }
    }

    private func update(time: CMTime, item: AVPlayerItem) {
        let total = item.duration.seconds
        if total.isFinite, total > 0 { duration = total }
        currentTime = time.seconds
        guard let duration, duration > 0 else { return }
        progress = currentTime / duration
    }

    private func finished() {
        isPlaying = false
        progress = 0
        currentTime = 0
        player?.seek(to: .zero)
    }
}
