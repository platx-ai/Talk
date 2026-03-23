//
//  UpdateCheckerTests.swift
//  TalkTests
//
//  UpdateChecker version comparison tests
//

import Testing
@testable import Talk

struct UpdateCheckerTests {

    // MARK: - isNewerVersion

    @Test func newerPatchVersion() {
        #expect(UpdateChecker.isNewerVersion("0.2.1", than: "0.2.0") == true)
    }

    @Test func newerMinorVersion() {
        #expect(UpdateChecker.isNewerVersion("0.3.0", than: "0.2.9") == true)
    }

    @Test func newerMajorVersion() {
        #expect(UpdateChecker.isNewerVersion("2.0.0", than: "1.9.9") == true)
    }

    @Test func sameVersion() {
        #expect(UpdateChecker.isNewerVersion("1.0.0", than: "1.0.0") == false)
    }

    @Test func olderVersion() {
        #expect(UpdateChecker.isNewerVersion("0.1.0", than: "0.2.0") == false)
    }

    @Test func differentSegmentCount() {
        #expect(UpdateChecker.isNewerVersion("1.1", than: "1.0.0") == true)
        #expect(UpdateChecker.isNewerVersion("1.0", than: "1.0.1") == false)
        #expect(UpdateChecker.isNewerVersion("1.0.0", than: "1.0") == false)
    }

    @Test func singleSegment() {
        #expect(UpdateChecker.isNewerVersion("2", than: "1") == true)
        #expect(UpdateChecker.isNewerVersion("1", than: "2") == false)
    }
}
