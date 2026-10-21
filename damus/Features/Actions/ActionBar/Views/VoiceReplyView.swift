//
//  VoiceReplyView.swift
//  damus
//
//  Hold-to-record sheet that publishes a NIP-A0 voice reply (kind 1244).
//

import SwiftUI

/// The sheet opened from the action bar's mic button.
///
/// Hold the big button to record, let go to stop. The note is then uploaded
/// with the user's default media uploader and published as a kind 1244 reply
/// whose content is the audio URL, threaded with the usual NIP-10 tags.
struct VoiceReplyView: View {
    let damus_state: DamusState
    let replying_to: NostrEvent

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceNoteRecorder()
    @StateObject private var upload = ImageUploadModel()

    /// The finished recording waiting to be sent.
    @State private var recording: (url: URL, duration: TimeInterval)? = nil
    @State private var sending = false
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 8)

            Text(title)
                .font(.headline)

            Text(timeLabel)
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()

            recordButton

            if let error {
                Text(error).font(.footnote).foregroundColor(.red).multilineTextAlignment(.center)
            }

            if recording != nil {
                reviewButtons
            } else {
                Text(hint)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.height(360)])
        .onDisappear { recorder.discard() }
    }

    /// The headline, which follows the three states: idle, recording, review.
    private var title: String {
        if sending { return NSLocalizedString("Sending voice reply…", comment: "Title while a voice reply uploads.") }
        if recording != nil { return NSLocalizedString("Send this voice reply?", comment: "Title when a voice note is recorded and awaiting send.") }
        if recorder.isRecording { return NSLocalizedString("Recording…", comment: "Title while recording a voice note.") }
        return NSLocalizedString("Voice reply", comment: "Title of the voice reply sheet.")
    }

    private var hint: String {
        NSLocalizedString("Hold the button to record, let go to stop.", comment: "Hint under the voice reply record button.")
    }

    private var timeLabel: String {
        let secs = Int(recording?.duration ?? recorder.elapsed)
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    /// The hold-to-record button. The ring pulses with the mic level.
    private var recordButton: some View {
        ZStack {
            Circle()
                .fill(DamusColors.purple.opacity(0.15))
                .frame(width: 120, height: 120)
                .scaleEffect(recorder.isRecording ? 1 + CGFloat(recorder.level) * 0.4 : 1)
                .animation(.easeOut(duration: 0.1), value: recorder.level)
            Circle()
                .fill(recorder.isRecording ? Color.red : DamusColors.purple)
                .frame(width: 88, height: 88)
            Image(systemName: recording == nil ? "mic.fill" : "waveform")
                .font(.system(size: 34))
                .foregroundColor(.white)
        }
        .opacity(sending ? 0.5 : 1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginRecordingIfNeeded() }
                .onEnded { _ in endRecording() }
        )
        .disabled(sending || recording != nil)
        .accessibilityLabel(NSLocalizedString("Hold to record", comment: "Accessibility label for the voice reply record button."))
    }

    private var reviewButtons: some View {
        HStack(spacing: 16) {
            Button(role: .destructive) {
                recorder.discard()
                recording = nil
                error = nil
            } label: {
                Label(NSLocalizedString("Discard", comment: "Button to throw away a recorded voice note."), systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(sending)

            Button {
                Task { await send() }
            } label: {
                Label(NSLocalizedString("Send", comment: "Button to publish a recorded voice note."), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DamusColors.purple)
            .disabled(sending)
        }
    }

    private func beginRecordingIfNeeded() {
        guard !recorder.isRecording, recording == nil, !sending else { return }
        error = nil
        Task {
            let ok = await recorder.start()
            if !ok {
                error = NSLocalizedString("Microphone access is needed to record a voice reply.", comment: "Error when the mic could not be started.")
            }
        }
    }

    private func endRecording() {
        guard recorder.isRecording else { return }
        recording = recorder.stop()
        if recording == nil {
            error = NSLocalizedString("That was too short — hold a bit longer.", comment: "Error when a voice note is under half a second.")
        }
    }

    /// Uploads the recording and publishes the kind 1244 reply.
    private func send() async {
        guard let recording else { return }
        sending = true
        defer { sending = false }

        let uploader = damus_state.settings.default_media_uploader
        let result = await upload.start(media: .audio(recording.url), uploader: uploader, mediaType: .normal, keypair: damus_state.keypair)

        guard case .success(let urlString) = result else {
            error = NSLocalizedString("Upload failed. Please try again.", comment: "Error when a voice note upload fails.")
            return
        }

        let relay = await damus_state.nostrNetwork.relaysForEvent(event: replying_to).first
        var tags = nip10_reply_tags(replying_to: replying_to, keypair: damus_state.keypair, relayURL: relay)
        tags.append(["p", replying_to.pubkey.hex()])
        tags.append(["imeta", "url \(urlString)", "m audio/mp4", "duration \(Int(recording.duration.rounded()))"])

        let post = NostrPost(content: urlString, kind: .voice_reply, tags: tags)
        notify(.post(.post(post)))

        recorder.discard()
        dismiss()
    }
}
