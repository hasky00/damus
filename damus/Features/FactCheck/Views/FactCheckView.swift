//
//  FactCheckView.swift
//  damus
//
//  Damus Labs: the sheet where you give a note a fact-check verdict,
//  or ask the Sniff agent to look into it.
//

import SwiftUI

struct FactCheckView: View {
    let damus_state: DamusState
    let note: NostrEvent
    let keypair: FullKeypair

    @State private var verdict: FactVerdict? = nil
    @State private var source_text: String = ""
    @State private var comment: String = ""
    @State private var published: Bool = false
    @State private var asking_sniff: Bool = false
    @State private var sniff_asked: Bool = false
    @State private var error_text: String? = nil

    @Environment(\.dismiss) var dismiss

    var source_url: URL? {
        let trimmed = source_text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://" + trimmed)
    }

    var source_is_valid: Bool {
        source_text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source_url != nil
    }

    var agent_url: URL? {
        let s = damus_state.settings.fact_check_agent_url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        NavigationStack {
            Group {
                if published {
                    done_view
                } else {
                    form_view
                }
            }
            .navigationTitle(NSLocalizedString("Fact check", comment: "Title of the fact check sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Close", comment: "Button to close the fact check sheet")) { dismiss() }
                }
            }
        }
    }

    var done_view: some View {
        VStack(spacing: 16) {
            Spacer()
            PawBadge(verdict: verdict ?? .checks_out, size: 44)
            Text("Verdict published", comment: "Shown after a fact check verdict has been sent")
                .font(.title2.bold())
            Text("It now shows under the note for people who follow you, and any client that reads NIP-32 labels.", comment: "Explanation after a fact check verdict has been published")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal)
            Spacer()
            Button(NSLocalizedString("Done", comment: "Button to close the fact check sheet after publishing")) { dismiss() }
                .buttonStyle(GradientButtonStyle())
                .padding(.bottom)
        }
        .padding()
    }

    var form_view: some View {
        Form {
            Section {
                Text(note.content.trimmingCharacters(in: .whitespacesAndNewlines))
                    .lineLimit(4)
                    .font(.callout)
                    .foregroundColor(.gray)
            } header: {
                Text("The note", comment: "Header above the note being fact checked")
            }

            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(FactVerdict.pickable) { v in
                        Button {
                            verdict = v
                        } label: {
                            HStack(spacing: 8) {
                                PawBadge(verdict: v, size: 16)
                                Text(v.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(v.tint.opacity(0.18))
                            .foregroundColor(v.tint)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(verdict == v ? v.tint : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Your verdict", comment: "Header above the fact check verdict buttons")
            } footer: {
                Text("Published as a public label others can see. Your words, your name.", comment: "Footer explaining that a fact check verdict is public")
            }

            Section {
                TextField(NSLocalizedString("Source link (optional)", comment: "Placeholder for the fact check source URL"), text: $source_text)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(NSLocalizedString("One line: what's actually true?", comment: "Placeholder for the fact check comment"), text: $comment, axis: .vertical)
                    .lineLimit(1...4)
            } footer: {
                if !source_is_valid {
                    Text("That doesn't look like a link.", comment: "Shown when the fact check source is not a valid URL")
                        .foregroundColor(.red)
                }
            }

            Section {
                Button {
                    Task { await publish() }
                } label: {
                    Text("Publish verdict", comment: "Button that publishes a fact check verdict")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(verdict == nil || !source_is_valid)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if agent_url != nil {
                Section {
                    Button {
                        Task { await ask_sniff() }
                    } label: {
                        HStack {
                            if asking_sniff {
                                ProgressView()
                            } else {
                                PawBadge(verdict: .satire, size: 16)
                            }
                            Text(sniff_asked
                                 ? NSLocalizedString("Sniff is on it", comment: "Shown after asking the Sniff fact check agent")
                                 : NSLocalizedString("Ask Sniff", comment: "Button that asks the Sniff fact check agent to check a note"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(asking_sniff || sniff_asked)
                } footer: {
                    Text("Sniff is a fact-checking agent from Hasky Labs. It reads sources and publishes its own verdict under the note. Only when you ask.", comment: "Footer explaining the Sniff fact check agent")
                }
            }

            if let error_text {
                Section {
                    Text(error_text).foregroundColor(.red)
                }
            }
        }
    }

    func publish() async {
        guard let verdict else { return }
        guard let ev = FactCheckLabel.make(note: note, verdict: verdict, source: source_url, comment: comment.trimmingCharacters(in: .whitespacesAndNewlines), keypair: keypair) else {
            error_text = NSLocalizedString("Could not sign the verdict.", comment: "Error when a fact check event could not be created")
            return
        }
        await damus_state.nostrNetwork.postbox.send(ev)
        FactCheckStore.shared.add(event: ev)
        published = true
    }

    func ask_sniff() async {
        guard let agent_url else { return }
        asking_sniff = true
        defer { asking_sniff = false }

        var req = URLRequest(url: agent_url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "note_id": note.id.hex(),
            "pubkey": note.pubkey.hex(),
            "content": note.content,
            "asked_by": keypair.pubkey.hex(),
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                error_text = NSLocalizedString("Sniff didn't answer. Try again in a bit.", comment: "Error when the fact check agent could not be reached")
                return
            }
            sniff_asked = true
        } catch {
            error_text = NSLocalizedString("Sniff didn't answer. Try again in a bit.", comment: "Error when the fact check agent could not be reached")
        }
    }
}

/// The paw-print badge used for fact check verdicts.
struct PawBadge: View {
    let verdict: FactVerdict
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: "pawprint.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundColor(verdict.tint)
    }
}

extension FactVerdict {
    var tint: Color {
        switch self {
        case .checks_out: return Color(red: 0.30, green: 0.82, blue: 0.48)
        case .needs_context: return Color(red: 1.00, green: 0.71, blue: 0.28)
        case .misleading, .does_not_hold_up: return Color(red: 1.00, green: 0.42, blue: 0.48)
        case .satire: return Color(red: 0.77, green: 0.55, blue: 1.00)
        }
    }
}

struct FactCheckView_Previews: PreviewProvider {
    static var previews: some View {
        FactCheckView(damus_state: test_damus_state, note: test_note, keypair: test_keypair.to_full()!)
    }
}
