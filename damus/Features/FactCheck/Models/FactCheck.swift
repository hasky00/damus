//
//  FactCheck.swift
//  damus
//
//  Damus Labs: community fact checks as NIP-32 labels (kind 1985,
//  namespace "fact-check"). A verdict is just another label event, so
//  any client that understands NIP-32 can read it. The "Sniff" agent
//  publishes the same kind of label from its own key.
//

import Foundation

/// The verdict a fact check gives a note. Raw values are the `l` tag values on the wire.
enum FactVerdict: String, CaseIterable, Identifiable {
    case checks_out = "true"
    case needs_context = "needs-context"
    case misleading = "misleading"
    case does_not_hold_up = "false"
    case satire = "satire"

    var id: String { rawValue }

    /// The four verdicts a person can pick in the sheet. `misleading` is still
    /// accepted when it arrives from other clients, it is just not offered as a button.
    static let pickable: [FactVerdict] = [.checks_out, .needs_context, .does_not_hold_up, .satire]

    var title: String {
        switch self {
        case .checks_out:
            return NSLocalizedString("Checks out", comment: "Fact check verdict: the claim is accurate")
        case .needs_context:
            return NSLocalizedString("Needs context", comment: "Fact check verdict: the claim is missing important context")
        case .misleading:
            return NSLocalizedString("Misleading", comment: "Fact check verdict: the claim is misleading")
        case .does_not_hold_up:
            return NSLocalizedString("Doesn't hold up", comment: "Fact check verdict: the claim is false")
        case .satire:
            return NSLocalizedString("Satire", comment: "Fact check verdict: the note is satire or a joke")
        }
    }

    /// Higher means more serious. Used to break ties when summarising several verdicts.
    var severity: Int {
        switch self {
        case .checks_out: return 0
        case .satire: return 1
        case .needs_context: return 2
        case .misleading: return 3
        case .does_not_hold_up: return 4
        }
    }
}

/// One fact-check label, parsed from a kind 1985 event.
struct FactCheckLabel: Identifiable, Equatable {
    let id: NoteId            // id of the label event
    let author: Pubkey
    let note_id: NoteId       // the note being checked
    let verdict: FactVerdict
    let source: URL?
    let comment: String
    let created_at: UInt32

    static let namespace = "fact-check"
    static let kind: UInt32 = 1985

    /// Parse a kind 1985 event. Returns nil unless it is a fact-check label pointing at a note.
    init?(event ev: NostrEvent) {
        guard ev.kind == FactCheckLabel.kind else { return nil }

        var in_namespace = false
        var verdict: FactVerdict? = nil
        var note_id: NoteId? = nil
        var source: URL? = nil

        for tag in ev.tags {
            guard tag.count >= 2 else { continue }
            let key = tag[0].string()
            let value = tag[1].string()
            switch key {
            case "L":
                if value == FactCheckLabel.namespace { in_namespace = true }
            case "l":
                // ["l", <verdict>, "fact-check"]
                if tag.count >= 3, tag[2].string() == FactCheckLabel.namespace, let v = FactVerdict(rawValue: value) {
                    verdict = v
                }
            case "e":
                if note_id == nil { note_id = NoteId(hex: value) }
            case "r":
                if source == nil { source = URL(string: value) }
            default:
                break
            }
        }

        guard in_namespace, let verdict, let note_id else { return nil }

        self.id = ev.id
        self.author = ev.pubkey
        self.note_id = note_id
        self.verdict = verdict
        self.source = source
        self.comment = ev.content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.created_at = ev.created_at
    }

    /// Build the tags for a new fact-check label on `note`.
    static func tags(note: NostrEvent, verdict: FactVerdict, source: URL?) -> [[String]] {
        var tags: [[String]] = [
            ["L", namespace],
            ["l", verdict.rawValue, namespace],
            ["e", note.id.hex()],
            ["p", note.pubkey.hex()],
        ]
        if let source {
            tags.append(["r", source.absoluteString])
        }
        return tags
    }

    /// Create and sign a fact-check label event.
    static func make(note: NostrEvent, verdict: FactVerdict, source: URL?, comment: String, keypair: FullKeypair) -> NostrEvent? {
        return NostrEvent(content: comment, keypair: keypair.to_keypair(), kind: kind, tags: tags(note: note, verdict: verdict, source: source))
    }
}

/// In-memory store of fact-check labels, keyed by the note they check.
/// Fed by HomeModel (home subscription, authors = follows) and by anything
/// else that happens to receive kind 1985 events.
@MainActor
final class FactCheckStore: ObservableObject {
    static let shared = FactCheckStore()

    /// Labels per checked note, newest first. One label per author (latest wins).
    @Published private(set) var labels: [NoteId: [FactCheckLabel]] = [:]
    private var seen: Set<NoteId> = []

    /// Pubkey of the Sniff agent, once it has a key. Labels from it get a paw icon.
    var agent_pubkey: Pubkey? = nil

    func add(event ev: NostrEvent) {
        guard !seen.contains(ev.id), let label = FactCheckLabel(event: ev) else { return }
        seen.insert(ev.id)

        var list = labels[label.note_id] ?? []
        if let idx = list.firstIndex(where: { $0.author == label.author }) {
            // keep the newest verdict from each author
            guard list[idx].created_at < label.created_at else { return }
            list.remove(at: idx)
        }
        list.append(label)
        list.sort { $0.created_at > $1.created_at }
        labels[label.note_id] = list
    }

    func labels(for note_id: NoteId) -> [FactCheckLabel] {
        return labels[note_id] ?? []
    }

    func is_agent(_ pubkey: Pubkey) -> Bool {
        return agent_pubkey == pubkey
    }

    /// The verdict to show in the collapsed banner: the most common one, ties going to the more serious.
    static func summary(of labels: [FactCheckLabel]) -> FactVerdict? {
        guard !labels.isEmpty else { return nil }
        var counts: [FactVerdict: Int] = [:]
        for l in labels { counts[l.verdict, default: 0] += 1 }
        return counts.max { a, b in
            if a.value != b.value { return a.value < b.value }
            return a.key.severity < b.key.severity
        }?.key
    }
}
