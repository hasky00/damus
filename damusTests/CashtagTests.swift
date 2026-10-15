//
//  CashtagTests.swift
//  damusTests
//

import XCTest
@testable import damus

final class CashtagTests: XCTestCase {

    func testExtractSingle() {
        XCTAssertEqual(Cashtag.extract(from: "buying $BTC today"), [Cashtag(symbol: "BTC")])
    }

    func testExtractMultipleDeduped() {
        let tags = Cashtag.extract(from: "$BTC vs $ETH, and $BTC again")
        XCTAssertEqual(tags.map(\.symbol), ["BTC", "ETH"])
    }

    func testIgnoresLowercaseAndNumbers() {
        XCTAssertTrue(Cashtag.extract(from: "$btc $100 $B $1BTC").isEmpty)
    }

    func testIgnoresEmbeddedDollar() {
        XCTAssertTrue(Cashtag.extract(from: "costs US$BTC lol").isEmpty)
    }

    func testPunctuationBoundary() {
        XCTAssertEqual(Cashtag.extract(from: "wen $BTC? ($ETH)").map(\.symbol), ["BTC", "ETH"])
    }

    func testCapsAtMaxPerNote() {
        let tags = Cashtag.extract(from: "$BTC $ETH $SOL $ADA $XRP $BTC")
        XCTAssertEqual(tags.map(\.symbol), ["BTC", "ETH", "SOL"])
        XCTAssertEqual(tags.count, Cashtag.maxPerNote)
    }

    func testBelowCapUnaffected() {
        XCTAssertEqual(Cashtag.extract(from: "$BTC $ETH").map(\.symbol), ["BTC", "ETH"])
    }

    func testZeroLimit() {
        XCTAssertTrue(Cashtag.extract(from: "$BTC", limit: 0).isEmpty)
    }

    func testParsePriceComputesChange() throws {
        let stats = Data(#"{"open":"100.00","high":"120","low":"90","last":"110.50","volume":"1"}"#.utf8)
        let price = try CashtagPriceService.parsePrice(symbol: "BTC", stats: stats, sparkline: nil)
        XCTAssertEqual(price.symbol, "BTC")
        XCTAssertEqual(price.price, 110.5)
        XCTAssertEqual(price.change24h, 10.5, accuracy: 0.0001)
    }

    func testParsePriceRejectsNonNumeric() {
        let stats = Data(#"{"open":"abc","last":"1"}"#.utf8)
        XCTAssertThrowsError(try CashtagPriceService.parsePrice(symbol: "BTC", stats: stats, sparkline: nil))
    }

    func testParseSparklineIsOldestFirstCloses() throws {
        // [time, low, high, open, close, volume], newest first
        let candles = Data("[[3,0,0,0,30,1],[2,0,0,0,20,1],[1,0,0,0,10,1]]".utf8)
        XCTAssertEqual(try CashtagPriceService.parseSparkline(candles), [10, 20, 30])
    }
}
