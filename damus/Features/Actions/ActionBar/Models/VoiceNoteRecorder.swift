//
//  VoiceNoteRecorder.swift
//  damus
//
//  Records a short voice note with the microphone for a NIP-A0 voice reply.
//

import AVFoundation
import Foundation

/// Records microphone audio to a temporary `.m4a` file and reports how long
/// the recording has been running, so the UI can show a live timer.
///
/// Usage: `start()` then `stop()`; `stop()` hands back the file URL and the
/// duration in seconds. Recordings longer than ``maxDuration`` stop on their own.
@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject {
    /// The longest a voice note may run; past this the recorder stops itself.
    static let maxDuration: TimeInterval = 120

    /// Seconds recorded so far, refreshed a few times per second while recording.
    @Published private(set) var elapsed: TimeInterval = 0
    /// Whether the microphone is currently capturing.
    @Published private(set) var isRecording = false
    /// Normalized mic level (0...1), for a simple pulsing indicator.
    @Published private(set) var level: Float = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    /// Where the current (or last) recording is written.
    private(set) var fileURL: URL?

    /// Asks for microphone permission and starts recording. Returns false when
    /// permission is denied or the recorder could not be set up.
    func start() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return false
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-note-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64_000,
        ]

        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        recorder.isMeteringEnabled = true
        guard recorder.record() else { return false }

        self.recorder = recorder
        self.fileURL = url
        self.elapsed = 0
        self.isRecording = true
        startTimer()
        return true
    }

    /// Stops recording and returns the file with its duration, or nil when
    /// nothing was recorded.
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        timer?.invalidate()
        timer = nil

        guard let recorder, let fileURL else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        isRecording = false
        level = 0
        restorePlaybackSession()

        guard duration > 0.3 else {
            discard()
            return nil
        }
        return (fileURL, duration)
    }

    /// Stops (if needed) and deletes the recording file.
    func discard() {
        if isRecording { _ = stop() }
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        elapsed = 0
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let recorder else { return }
        elapsed = recorder.currentTime
        recorder.updateMeters()
        // Average power is in dB from -160 to 0; map the useful -50...0 range to 0...1.
        let db = recorder.averagePower(forChannel: 0)
        level = max(0, min(1, (db + 50) / 50))

        if elapsed >= Self.maxDuration {
            _ = stop()
        }
    }

    /// Puts the shared audio session back the way the app configures it at
    /// launch (playback, mixing with other apps) so timeline videos keep working.
    private func restorePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .default, options: .mixWithOthers)
    }
}
