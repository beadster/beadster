//
//  DateUtilsTests.swift
//  Beadster
//
//  Unit tests for DateUtils
//

import XCTest
@testable import Shared

final class DateUtilsTests: XCTestCase {

    // MARK: - parseISO8601 Tests

    func testParseISO8601WithFractionalSeconds() {
        // Test with fractional seconds and timezone offset
        let dateString = "2025-10-28T14:30:45.123+02:00"
        let timestamp = DateUtils.parseISO8601(from: dateString)

        XCTAssertNotNil(timestamp, "Should parse date with fractional seconds")

        // Verify the timestamp is reasonable (around Oct 28, 2025)
        // 2025-10-28T14:30:45+02:00 = 2025-10-28T12:30:45Z
        if let timestamp = timestamp {
            let expectedTimestamp = 1761654645 // Correct UTC timestamp
            XCTAssertEqual(timestamp, expectedTimestamp, accuracy: 1, "Timestamp should be close to expected value")
        }
    }

    func testParseISO8601WithoutFractionalSeconds() {
        // Test without fractional seconds
        let dateString = "2025-10-28T14:30:45+02:00"
        let timestamp = DateUtils.parseISO8601(from: dateString)

        XCTAssertNotNil(timestamp, "Should parse date without fractional seconds")
    }

    func testParseISO8601WithUTC() {
        // Test with UTC (Z) timezone
        let dateString = "2025-10-28T12:30:45Z"
        let timestamp = DateUtils.parseISO8601(from: dateString)

        XCTAssertNotNil(timestamp, "Should parse date with UTC timezone")
    }

    func testParseISO8601WithUTCAndFractionalSeconds() {
        // Test with UTC and fractional seconds
        let dateString = "2025-10-28T12:30:45.123Z"
        let timestamp = DateUtils.parseISO8601(from: dateString)

        XCTAssertNotNil(timestamp, "Should parse date with UTC timezone and fractional seconds")
    }

    func testParseISO8601WithNegativeOffset() {
        // Test with negative timezone offset
        let dateString = "2025-10-28T14:30:45.123-05:00"
        let timestamp = DateUtils.parseISO8601(from: dateString)

        XCTAssertNotNil(timestamp, "Should parse date with negative timezone offset")
    }

    func testParseISO8601InvalidFormat() {
        // Test with invalid date format
        let invalidStrings = [
            "2025-10-28",                    // Missing time
            "2025-10-28 14:30:45",          // Space instead of T
            "28-10-2025T14:30:45Z",         // Wrong order
            "not a date",                    // Gibberish
            "",                              // Empty string
            "2025-10-28T14:30:45"           // Missing timezone
        ]

        for invalidString in invalidStrings {
            let timestamp = DateUtils.parseISO8601(from: invalidString)
            XCTAssertNil(timestamp, "Should return nil for invalid format: \(invalidString)")
        }
    }

    // MARK: - formatISO8601 Tests

    func testFormatISO8601FromTimestamp() {
        // Test formatting from Unix timestamp
        let timestamp = 1698499845 // 2023-10-28T12:30:45 UTC
        let formatted = DateUtils.formatISO8601(from: timestamp)

        // Should produce ISO8601 format with fractional seconds and timezone
        XCTAssertTrue(formatted.contains("2023-10-28"), "Should contain correct date")
        XCTAssertTrue(formatted.contains("T"), "Should contain T separator")
        XCTAssertTrue(formatted.contains(":"), "Should contain time")
        XCTAssertTrue(formatted.contains("Z") || formatted.contains("+") || formatted.contains("-"),
                     "Should contain timezone")
    }

    func testFormatISO8601FromDate() {
        // Test formatting from Date object
        let date = Date(timeIntervalSince1970: 1698499845)
        let formatted = DateUtils.formatISO8601(from: date)

        XCTAssertTrue(formatted.contains("2023-10-28"), "Should contain correct date")
        XCTAssertTrue(formatted.contains("T"), "Should contain T separator")
    }

    func testFormatISO8601CurrentDate() {
        // Test with current date
        let now = Date()
        let formatted = DateUtils.formatISO8601(from: now)

        // Should be parseable
        let parsed = DateUtils.parseISO8601(from: formatted)
        XCTAssertNotNil(parsed, "Formatted date should be parseable")
    }

    // MARK: - Round-trip Tests

    func testRoundTripParseAndFormat() {
        // Test that we can parse and format back to same value
        let originalTimestamp = 1698499845

        // Format to string
        let formatted = DateUtils.formatISO8601(from: originalTimestamp)

        // Parse back to timestamp
        let parsedTimestamp = DateUtils.parseISO8601(from: formatted)

        XCTAssertNotNil(parsedTimestamp, "Should be able to parse formatted string")
        XCTAssertEqual(parsedTimestamp, originalTimestamp, "Round-trip should preserve timestamp")
    }

    func testRoundTripWithDate() {
        // Test round-trip with Date object
        let originalDate = Date()
        let originalTimestamp = Int(originalDate.timeIntervalSince1970)

        // Format
        let formatted = DateUtils.formatISO8601(from: originalDate)

        // Parse back
        let parsedTimestamp = DateUtils.parseISO8601(from: formatted)

        XCTAssertNotNil(parsedTimestamp, "Should parse formatted date")
        XCTAssertEqual(parsedTimestamp, originalTimestamp, "Round-trip should preserve timestamp")
    }

    func testRoundTripWithExternalFormat() {
        // Test parsing dates from external systems (like bd CLI)
        let externalFormats = [
            "2025-10-28T12:30:45.123456Z",
            "2025-10-28T12:30:45Z",
            "2025-10-28T14:30:45+02:00",
            "2025-10-28T14:30:45.999+02:00"
        ]

        for externalFormat in externalFormats {
            let parsed = DateUtils.parseISO8601(from: externalFormat)
            XCTAssertNotNil(parsed, "Should parse external format: \(externalFormat)")

            // Verify we can format it back
            if let timestamp = parsed {
                let reformatted = DateUtils.formatISO8601(from: timestamp)
                let reparsed = DateUtils.parseISO8601(from: reformatted)
                XCTAssertEqual(reparsed, timestamp, "Re-parsing should give same timestamp for: \(externalFormat)")
            }
        }
    }

    // MARK: - Edge Cases

    func testEpochTime() {
        // Test Unix epoch (1970-01-01 00:00:00 UTC)
        let epochTimestamp = 0
        let formatted = DateUtils.formatISO8601(from: epochTimestamp)
        let parsed = DateUtils.parseISO8601(from: formatted)

        XCTAssertNotNil(parsed, "Should handle epoch time")
        XCTAssertEqual(parsed, epochTimestamp, "Epoch time should round-trip correctly")
    }

    func testFarFutureDate() {
        // Test a date far in the future (year 2100)
        let futureTimestamp = 4102444800 // 2100-01-01 00:00:00 UTC
        let formatted = DateUtils.formatISO8601(from: futureTimestamp)
        let parsed = DateUtils.parseISO8601(from: formatted)

        XCTAssertNotNil(parsed, "Should handle far future dates")
        XCTAssertEqual(parsed, futureTimestamp, "Far future date should round-trip correctly")
    }

    func testMultipleParsesConcurrently() {
        // Test thread safety with concurrent parsing
        let expectation = self.expectation(description: "Concurrent parsing")
        expectation.expectedFulfillmentCount = 10

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<10 {
            queue.async {
                let timestamp = 1698499845 + i
                let formatted = DateUtils.formatISO8601(from: timestamp)
                let parsed = DateUtils.parseISO8601(from: formatted)

                XCTAssertNotNil(parsed, "Concurrent parse should work")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0)
    }
}
