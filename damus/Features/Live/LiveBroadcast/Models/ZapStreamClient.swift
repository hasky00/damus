//
//  ZapStreamClient.swift
//  damus
//
//  Created by Hasky on 2026-10-15.
//

import Foundation

/// Minimal client for the zap.stream account API.
///
/// zap.stream publishes the kind 30311 live event for a stream itself, with
/// the broadcaster as host. Rather than publishing a second, competing event
/// from Damus, we tell zap.stream what title and summary to use and let it
/// carry them in the event it signs. Requests are authenticated with NIP-98
/// using the user's Nostr key, which is the same key they log into
/// zap.stream with.
struct ZapStreamClient {
    /// Base URL of the API, e.g. `https://api.zap.stream`.
    let apiBase: URL
    let keypair: Keypair

    enum ClientError: LocalizedError {
        case notZapStream
        case unauthorized
        case serverError(Int)

        var errorDescription: String? {
            switch self {
            case .notZapStream:
                return NSLocalizedString("Stream titles can only be set when streaming to zap.stream.", comment: "Error shown when the RTMP server is not a zap.stream host.")
            case .unauthorized:
                return NSLocalizedString("zap.stream rejected the request. Log in to zap.stream with this Nostr key first.", comment: "Error shown when zap.stream returns 401 for a NIP-98 request.")
            case .serverError(let code):
                return String(format: NSLocalizedString("zap.stream returned an error (%d).", comment: "Error shown when zap.stream returns an unexpected HTTP status."), code)
            }
        }
    }

    /// Works out which zap.stream API serves a given ingest server.
    ///
    /// Each region has its own ingest and API host; the ingest is
    /// `in.<region>.zap.stream` and the API is `api-<region>.zap.stream`, with
    /// the default region using plain `in.` and `api.`.
    ///
    /// - Parameter rtmpURL: The ingest URL from settings, such as `rtmp://in.ca.zap.stream:1935/good`.
    /// - Returns: The matching API base URL, or nil when the host is not zap.stream.
    static func apiBase(forIngest rtmpURL: String) -> URL? {
        guard let host = URL(string: rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased() else { return nil }
        guard host.hasSuffix(".zap.stream") else { return nil }
        // "in.ca.zap.stream" -> ["in", "ca", "zap", "stream"]; the region is the middle part if present.
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 3, parts.first == "in" else { return nil }
        let region = parts.count > 3 ? parts[1] : nil
        let apiHost = region.map { "api-\($0).zap.stream" } ?? "api.zap.stream"
        return URL(string: "https://\(apiHost)")
    }

    /// Sets the title and summary zap.stream will put on the next live event.
    ///
    /// Sends `PATCH /api/v1/event` with no stream id, which updates the
    /// account's default stream details.
    func updateStreamDetails(title: String, summary: String?) async throws {
        struct PatchEvent: Encodable {
            let title: String
            let summary: String?
        }
        let body = try JSONEncoder().encode(PatchEvent(title: title, summary: summary))
        let url = apiBase.appendingPathComponent("api/v1/event")
        let (_, response) = try await make_nip98_authenticated_request(method: .patch, url: url, payload: body, payload_type: .json, auth_keypair: keypair)
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw ClientError.unauthorized
        default: throw ClientError.serverError(http.statusCode)
        }
    }
}
