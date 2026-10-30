//
//  FactCheckBanner.swift
//  damus
//
//  Damus Labs: the small banner under a note that shows fact-check verdicts
//  from people you follow (and the Sniff agent). Tap to expand.
//

import SwiftUI

struct FactCheckBanner: View {
    let damus_state: DamusState
    let event: NostrEvent

    @ObservedObject private var store = FactCheckStore.shared
    @State private var expanded: Bool = false
    @State private var show_all: Bool = false

    var all_labels: [FactCheckLabel] {
        store.labels(for: event.id)
    }

    /// Labels from people you follow, yourself, or the Sniff agent.
    var trusted_labels: [FactCheckLabel] {
        all_labels.filter { l in
            damus_state.contacts.is_friend_or_self(l.author) || store.is_agent(l.author)
        }
    }

    var shown_labels: [FactCheckLabel] {
        show_all ? all_labels : trusted_labels
    }

    var hidden_count: Int {
        all_labels.count - trusted_labels.count
    }

    var body: some View {
        if let summary = FactCheckStore.summary(of: shown_labels), !shown_labels.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                header(summary: summary)
                if expanded {
                    ForEach(shown_labels) { label in
                        row(label)
                    }
                    if hidden_count > 0 {
                        Button {
                            show_all.toggle()
                        } label: {
                            Text(show_all
                                 ? NSLocalizedString("Only people I follow", comment: "Button that hides fact checks from people the user does not follow")
                                 : String(format: NSLocalizedString("Show %d more from people you don't follow", comment: "Button that reveals fact checks from people the user does not follow"), hidden_count))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(10)
            .background(summary.tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            }
        } else if hidden_count > 0 && !show_all {
            // Nothing from follows, but strangers have weighed in.
            Button {
                show_all = true
                expanded = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pawprint")
                    Text(String(format: NSLocalizedString("%d fact checks from people you don't follow", comment: "Collapsed note under a post when only strangers have fact checked it"), hidden_count))
                }
                .font(.caption)
                .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
    }

    func header(summary: FactVerdict) -> some View {
        HStack(spacing: 8) {
            PawBadge(verdict: summary, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(summary.tint)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    var subtitle: String {
        let labels = shown_labels
        let agent = labels.filter { store.is_agent($0.author) }.count
        let people = labels.count - agent
        let sources = labels.filter { $0.source != nil }.count

        var parts: [String] = []
        if people > 0 {
            parts.append(String(format: NSLocalizedString("%d people you follow", comment: "Count of followed people who fact checked a note"), people))
        }
        if agent > 0 {
            parts.append(NSLocalizedString("1 Sniff check", comment: "Indicates the Sniff agent has fact checked a note"))
        }
        if sources > 0 {
            parts.append(String(format: NSLocalizedString("%d sources", comment: "Count of fact check source links"), sources))
        }
        parts.append(NSLocalizedString("tap to see", comment: "Hint to tap the fact check banner"))
        return parts.joined(separator: "  ·  ")
    }

    func row(_ label: FactCheckLabel) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if store.is_agent(label.author) {
                PawBadge(verdict: .satire, size: 14)
                    .padding(.top, 2)
            } else {
                ProfilePicView(pubkey: label.author, size: 20, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation, damusState: damus_state)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if store.is_agent(label.author) {
                        Text("Sniff", comment: "Name of the fact check agent")
                            .font(.caption.weight(.semibold))
                        Text("agent", comment: "Label marking the Sniff fact check as coming from an agent")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    } else {
                        Text(Profile.displayName(profile: try? damus_state.profiles.lookup(id: label.author), pubkey: label.author).username.truncate(maxLength: 24))
                            .font(.caption.weight(.semibold))
                    }
                    PawBadge(verdict: label.verdict, size: 10)
                    Text(label.verdict.title)
                        .font(.caption2)
                        .foregroundColor(label.verdict.tint)
                }
                if !label.comment.isEmpty {
                    Text(label.comment)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let source = label.source {
                    Link(destination: source) {
                        Text(source.host ?? source.absoluteString)
                            .font(.caption)
                            .underline()
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
    }
}

struct FactCheckBanner_Previews: PreviewProvider {
    static var previews: some View {
        FactCheckBanner(damus_state: test_damus_state, event: test_note)
    }
}
