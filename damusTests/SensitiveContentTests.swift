//
//  SensitiveContentTests.swift
//  damusTests
//

import XCTest
@testable import damus

final class SensitiveContentTests: XCTestCase {

    private func note(tags: [[String]]) throws -> NostrEvent {
        return try XCTUnwrap(NostrEvent(content: "hello", keypair: test_keypair, tags: tags))
    }

    func testPlainNoteIsNotSensitive() throws {
        XCTAssertNil(sensitive_content_reason(ev: try note(tags: [])))
        XCTAssertNil(sensitive_content_reason(ev: try note(tags: [["t", "nostr"]])))
    }

    func testContentWarningWithReason() throws {
        let ev = try note(tags: [["content-warning", "spoilers"]])
        XCTAssertEqual(sensitive_content_reason(ev: ev), .content_warning(reason: "spoilers"))
    }

    func testContentWarningWithoutReason() throws {
        XCTAssertEqual(sensitive_content_reason(ev: try note(tags: [["content-warning"]])), .content_warning(reason: nil))
        XCTAssertEqual(sensitive_content_reason(ev: try note(tags: [["content-warning", "  "]])), .content_warning(reason: nil))
    }

    func testNsfwHashtag() throws {
        XCTAssertEqual(sensitive_content_reason(ev: try note(tags: [["t", "NSFW"]])), .nsfw_hashtag)
    }

    func testContentWarningTakesPrecedenceOverNsfw() throws {
        let ev = try note(tags: [["t", "nsfw"], ["content-warning", "gore"]])
        XCTAssertEqual(sensitive_content_reason(ev: ev), .content_warning(reason: "gore"))
    }
}
