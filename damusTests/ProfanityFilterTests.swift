//
//  ProfanityFilterTests.swift
//  damusTests
//

import XCTest
@testable import damus

final class ProfanityFilterTests: XCTestCase {

    func testDetectsProfanityCaseInsensitive() {
        XCTAssertTrue(ProfanityFilter.contains_profanity("what the FUCK"))
        XCTAssertTrue(ProfanityFilter.contains_profanity("Shit happens"))
    }

    func testDetectsStemSuffixes() {
        XCTAssertTrue(ProfanityFilter.contains_profanity("this is fucking great"))
        XCTAssertTrue(ProfanityFilter.contains_profanity("I was pissed"))
    }

    func testDetectsExactWordPlurals() {
        XCTAssertTrue(ProfanityFilter.contains_profanity("bunch of asses"))
        XCTAssertTrue(ProfanityFilter.contains_profanity("dicks"))
    }

    func testIgnoresInnocentWordsContainingProfanity() {
        XCTAssertFalse(ProfanityFilter.contains_profanity("my assistant will assume the class is in Scunthorpe"))
        XCTAssertFalse(ProfanityFilter.contains_profanity("cocktail at the Dickens museum"))
        XCTAssertFalse(ProfanityFilter.contains_profanity("hello world"))
    }

    func testMaskKeepsFirstLetter() {
        XCTAssertEqual(ProfanityFilter.mask("what the fuck"), "what the f***")
        XCTAssertEqual(ProfanityFilter.mask("Shit and more shit!"), "S*** and more s***!")
    }

    func testMaskLeavesCleanTextUnchanged() {
        XCTAssertEqual(ProfanityFilter.mask("a classic assistant"), "a classic assistant")
    }

    func testMaskAttributedKeepsSurroundingAttributes() {
        var link = AttributedString("damus.io")
        link.link = URL(string: "https://damus.io")
        let attributed = AttributedString("shit, see ") + link

        let masked = ProfanityFilter.mask(attributed)

        XCTAssertEqual(String(masked.characters), "s***, see damus.io")
        let linked = masked.runs.compactMap { run in run.link == nil ? nil : String(masked[run.range].characters) }
        XCTAssertEqual(linked, ["damus.io"])
    }

    func testProfanityTimelineFilter() throws {
        let clean = try XCTUnwrap(NostrEvent(content: "good morning", keypair: test_keypair))
        let dirty = try XCTUnwrap(NostrEvent(content: "good fucking morning", keypair: test_keypair))
        XCTAssertTrue(profanity_filter(ev: clean))
        XCTAssertFalse(profanity_filter(ev: dirty))
    }
}
