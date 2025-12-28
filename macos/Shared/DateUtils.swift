//
//  DateUtils.swift
//  Beadster
//
//  Centralized date parsing and formatting utilities
//

import Foundation

enum DateUtils {
    /// Shared ISO8601 formatters with different options
    private static var formatters: [ISO8601DateFormatter] = {
        // Try with fractional seconds first
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]

        // Fallback without fractional seconds
        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime, .withTimeZone]

        return [withFractional, withoutFractional]
    }()

    /// Parse ISO8601 date string to Unix timestamp
    /// Handles both timezone offsets (+02:00) and UTC (Z) formats
    /// Tries with and without fractional seconds
    static func parseISO8601(from dateString: String) -> Int? {
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return Int(date.timeIntervalSince1970)
            }
        }
        return nil
    }

    /// Format Unix timestamp to ISO8601 string with timezone and fractional seconds
    static func formatISO8601(from timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return formatters[0].string(from: date)
    }

    /// Format Date to ISO8601 string with timezone and fractional seconds
    static func formatISO8601(from date: Date) -> String {
        return formatters[0].string(from: date)
    }
}
