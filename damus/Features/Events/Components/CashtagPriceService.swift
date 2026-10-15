//
//  CashtagPriceService.swift
//  damus
//
//  Fetches ticker prices from Coinbase's public, keyless Exchange API with a
//  small in-memory cache so a busy timeline doesn't hammer the API.
//

import Foundation

/// Price snapshot for a single ticker.
struct CashtagPrice: Equatable {
    /// Ticker, e.g. "BTC".
    let symbol: String
    /// Current price in USD.
    let price: Double
    /// 24h change as a percentage, e.g. -2.35 for -2.35%.
    let change24h: Double
    /// Hourly closes for the last 24h, oldest first. Optional so the card
    /// still renders if the candles request fails.
    let sparkline: [Double]?
}

/// Loads and caches `CashtagPrice` values. Safe to call from any context;
/// all network work runs off the main thread.
actor CashtagPriceService {
    static let shared = CashtagPriceService()

    /// Base URL for Coinbase Exchange products.
    /// Stats: `{base}/{SYMBOL}-USD/stats`, candles: `{base}/{SYMBOL}-USD/candles`.
    static let baseURL = URL(string: "https://api.exchange.coinbase.com/products")!

    /// Number of hourly candles used for the sparkline.
    static let sparklinePoints = 24

    /// How long a cached price stays fresh.
    private let ttl: TimeInterval = 60

    /// How long a failed lookup is remembered before it may be retried.
    private let failureCooldown: TimeInterval = 30

    private struct Entry {
        let price: CashtagPrice
        let fetchedAt: Date
    }

    private var cache: [String: Entry] = [:]
    private var inflight: [String: Task<CashtagPrice, Error>] = [:]
    /// Symbols whose last lookup failed, mapped to when it failed.
    private var failures: [String: Date] = [:]

    /// Returns a price for `symbol`, from cache if fresh, otherwise fetched.
    /// Concurrent callers for the same symbol share a single request, and a
    /// symbol that recently failed throws immediately until the cooldown ends.
    ///
    /// - Parameter symbol: Ticker, case-insensitive, e.g. "btc" or "BTC".
    /// - Returns: The latest price snapshot.
    /// - Throws: `URLError` on network/HTTP failure or cooldown, or a decoding error.
    func price(for symbol: String) async throws -> CashtagPrice {
        let key = symbol.uppercased()

        if let entry = cache[key], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.price
        }

        if let failedAt = failures[key], Date().timeIntervalSince(failedAt) < failureCooldown {
            throw URLError(.resourceUnavailable)
        }

        if let task = inflight[key] {
            return try await task.value
        }

        let task = Task<CashtagPrice, Error> { try await Self.fetch(symbol: key) }

        inflight[key] = task
        defer { inflight[key] = nil }

        do {
            let price = try await task.value
            cache[key] = Entry(price: price, fetchedAt: Date())
            failures[key] = nil
            return price
        } catch {
            Log.info("Cashtag price lookup failed for %@: %@", for: .networking, key, error.localizedDescription)
            failures[key] = Date()
            throw error
        }
    }

    /// Fetches 24h stats and hourly candles for `symbol` in parallel.
    /// The sparkline is best-effort: a candles failure still yields a price.
    ///
    /// - Parameter symbol: Upper-cased ticker, e.g. "BTC".
    /// - Returns: A price snapshot built from the Coinbase responses.
    private static func fetch(symbol: String) async throws -> CashtagPrice {
        let product = baseURL.appendingPathComponent("\(symbol)-USD")
        var candlesURL = URLComponents(url: product.appendingPathComponent("candles"), resolvingAgainstBaseURL: false)!
        candlesURL.queryItems = [URLQueryItem(name: "granularity", value: "3600")]

        async let statsData = get(product.appendingPathComponent("stats"))
        async let candlesData = try? get(candlesURL.url!)

        let stats = try await statsData
        let sparkline = await candlesData.flatMap { try? parseSparkline($0) }
        return try parsePrice(symbol: symbol, stats: stats, sparkline: sparkline)
    }

    /// Performs a GET and returns the body, throwing on non-2xx responses.
    private static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Coinbase `/stats` body. Numbers are sent as strings.
    private struct Stats: Decodable {
        let open: String
        let last: String
    }

    /// Builds a `CashtagPrice` from a Coinbase `/stats` response.
    ///
    /// - Parameters:
    ///   - symbol: Ticker the stats belong to.
    ///   - stats: Raw `/stats` JSON body.
    ///   - sparkline: Optional closes, oldest first.
    /// - Returns: The price with 24h change computed from `open` and `last`.
    /// - Throws: A decoding error, or `URLError(.cannotParseResponse)` for non-numeric values.
    static func parsePrice(symbol: String, stats: Data, sparkline: [Double]?) throws -> CashtagPrice {
        let decoded = try JSONDecoder().decode(Stats.self, from: stats)
        guard let open = Double(decoded.open), let last = Double(decoded.last) else {
            throw URLError(.cannotParseResponse)
        }
        let change = open > 0 ? (last - open) / open * 100 : 0
        return CashtagPrice(symbol: symbol, price: last, change24h: change, sparkline: sparkline)
    }

    /// Extracts closing prices from a Coinbase `/candles` response.
    ///
    /// Each candle is `[time, low, high, open, close, volume]`, newest first.
    ///
    /// - Parameter candles: Raw `/candles` JSON body.
    /// - Returns: The last `sparklinePoints` closes, oldest first.
    /// - Throws: A decoding error if the body isn't an array of number arrays.
    static func parseSparkline(_ candles: Data) throws -> [Double] {
        let rows = try JSONDecoder().decode([[Double]].self, from: candles)
        let closes = rows.prefix(sparklinePoints).compactMap { $0.count > 4 ? $0[4] : nil }
        return closes.reversed()
    }
}
