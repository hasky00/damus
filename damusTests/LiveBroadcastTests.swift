//
//  LiveBroadcastTests.swift
//  damusTests
//
//  Created by Hasky on 2026-10-15.
//

import XCTest
@testable import damus

final class LiveBroadcastTests: XCTestCase {
    func testIngestURLJoinsServerAndKey() {
        let url = LiveBroadcaster.ingestURL(server: "rtmp://in.ca.zap.stream:1935/good", key: "abc123")
        XCTAssertEqual(url?.absoluteString, "rtmp://in.ca.zap.stream:1935/good/abc123")
    }

    func testIngestURLTrimsWhitespace() {
        let url = LiveBroadcaster.ingestURL(server: " rtmp://in.zap.stream:1935/good \n", key: " key ")
        XCTAssertEqual(url?.absoluteString, "rtmp://in.zap.stream:1935/good/key")
    }

    func testIngestURLRejectsNonRTMP() {
        XCTAssertNil(LiveBroadcaster.ingestURL(server: "https://in.zap.stream/good", key: "key"))
        XCTAssertNil(LiveBroadcaster.ingestURL(server: "", key: "key"))
        XCTAssertNil(LiveBroadcaster.ingestURL(server: "rtmp://in.zap.stream/good", key: ""))
    }

    func testAPIBaseForRegionalIngest() {
        XCTAssertEqual(ZapStreamClient.apiBase(forIngest: "rtmp://in.ca.zap.stream:1935/good")?.absoluteString, "https://api-ca.zap.stream")
    }

    func testAPIBaseForDefaultIngest() {
        XCTAssertEqual(ZapStreamClient.apiBase(forIngest: "rtmp://in.zap.stream:1935/good")?.absoluteString, "https://api.zap.stream")
    }

    func testAPIBaseRejectsOtherHosts() {
        XCTAssertNil(ZapStreamClient.apiBase(forIngest: "rtmp://162.35.161.17:1935/live"))
        XCTAssertNil(ZapStreamClient.apiBase(forIngest: "rtmp://api.zap.stream/good"))
    }
}
