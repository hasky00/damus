//
//  SpotifyEmbedView.swift
//  damus
//
//  Rich card for open.spotify.com links, using Spotify's public embed player.
//

import SwiftUI
import WebKit

/// A Spotify link worth showing as a card: a track, album, playlist, artist,
/// podcast show or episode.
struct SpotifyLink: Equatable {
    /// The kind of thing the link points at, as it appears in the URL path.
    enum Kind: String {
        case track, album, playlist, artist, show, episode

        /// Height Spotify's embed uses for this kind. Tracks and episodes get
        /// the compact player; collections show a short tracklist.
        var embedHeight: CGFloat {
            switch self {
            case .track, .episode: return 80
            case .album, .playlist, .artist, .show: return 152
            }
        }
    }

    let kind: Kind
    let id: String

    /// Parses `https://open.spotify.com/<kind>/<id>` (with an optional locale
    /// segment such as `/intl-de/`) and `spotify:<kind>:<id>` URIs.
    init?(url: URL) {
        if url.scheme == "spotify" {
            let parts = url.absoluteString.split(separator: ":")
            guard parts.count == 3, let kind = Kind(rawValue: String(parts[1])) else { return nil }
            self.kind = kind
            self.id = String(parts[2])
            return
        }

        guard let host = url.host?.lowercased(), host == "open.spotify.com" || host == "play.spotify.com" else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        guard segments.count >= 2, let kind = Kind(rawValue: segments[0]) else { return nil }
        let id = segments[1]
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        self.kind = kind
        self.id = id
    }

    /// The embed player page for this link.
    var embedURL: URL {
        URL(string: "https://open.spotify.com/embed/\(kind.rawValue)/\(id)?utm_source=generator&theme=0")!
    }

    /// The first Spotify link among `urls`, if any.
    static func first(in urls: [URL]) -> SpotifyLink? {
        for url in urls {
            if let link = SpotifyLink(url: url) { return link }
        }
        return nil
    }

    /// Scans raw note text for the first Spotify link. Used as a fallback so the
    /// card does not depend on the note's parsed URL list being ready.
    static func first(inContent content: String) -> SpotifyLink? {
        let pattern = #"https?://(?:open|play)\.spotify\.com/\S+|spotify:(?:track|album|playlist|artist|show|episode):[A-Za-z0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(content.startIndex..., in: content)
        for match in regex.matches(in: content, range: range) {
            guard let r = Range(match.range, in: content) else { continue }
            let raw = content[r].trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}\"'"))
            guard let url = URL(string: String(raw)), let link = SpotifyLink(url: url) else { continue }
            return link
        }
        return nil
    }
}

/// Shows a Spotify link as its embed player: cover art, title, artist and a
/// play button for the preview, sized to the kind of content.
struct SpotifyEmbedView: View {
    let link: SpotifyLink
    @Environment(\.openURL) private var openURL

    var body: some View {
        SpotifyWebView(url: link.embedURL, openExternal: { openURL($0) })
            .frame(height: link.kind.embedHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(NSLocalizedString("Spotify player", comment: "Accessibility label for an embedded Spotify player."))
    }
}

/// Minimal web view for the embed page: transparent, non-scrolling, and
/// allowed to play audio inline without an extra tap.
private struct SpotifyWebView: UIViewRepresentable {
    let url: URL
    /// Opens a link outside the embed (Spotify app or Safari). Injected rather
    /// than using UIApplication.shared, which the share extension cannot use.
    let openExternal: (URL) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url, !context.coordinator.isLoading(url) else { return }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator(openExternal: openExternal) }

    /// Keeps taps inside the embed, and hands anything that tries to leave it
    /// (the Spotify logo, "Save on Spotify") to the system so the Spotify app
    /// or Safari opens instead of navigating the card away.
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loading: URL?
        private let openExternal: (URL) -> Void

        init(openExternal: @escaping (URL) -> Void) {
            self.openExternal = openExternal
        }

        func isLoading(_ url: URL) -> Bool { loading == url }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            loading = webView.url
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loading = nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else { return decisionHandler(.allow) }
            let isEmbed = target.host == "open.spotify.com" && target.path.hasPrefix("/embed")
            let isInitialLoad = webView.url == nil
            guard navigationAction.targetFrame?.isMainFrame == true, !isEmbed, !isInitialLoad else {
                return decisionHandler(.allow)
            }
            openExternal(target)
            decisionHandler(.cancel)
        }
    }
}
