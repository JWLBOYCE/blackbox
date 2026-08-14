import Foundation
import Testing
@testable import OpenPilotLogbook

@Suite("Zulu date editing")
struct ZuluDateEditingTests {
    @Test("A summer-time wall clock is stored as the same Zulu time")
    func summerTimeEntryDoesNotShiftByBST() throws {
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let original = try isoDate("2026-07-04T12:34:41Z")
        let pickerValue = try localDate(
            year: 2026,
            month: 7,
            day: 4,
            hour: 9,
            minute: 5,
            timeZone: london
        )

        let stored = ZuluDateEditing.storedValue(
            from: pickerValue,
            preserving: original,
            component: .time,
            in: london
        )

        #expect(stored == (try isoDate("2026-07-04T09:05:00Z")))
    }

    @Test("The native picker's local wall clock presents UTC components")
    func displayAdapterPresentsZuluComponentsInSummer() throws {
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let stored = try isoDate("2026-07-04T09:05:00Z")
        let pickerValue = ZuluDateEditing.displayValue(for: stored, in: london)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: pickerValue)

        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 4)
        #expect(components.hour == 9)
        #expect(components.minute == 5)
    }

    @Test("Changing the UTC date preserves the stored UTC time")
    func dateEntryPreservesZuluTime() throws {
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let original = try isoDate("2026-07-04T09:05:37Z")
        let pickerValue = try localDate(
            year: 2026,
            month: 8,
            day: 13,
            hour: 16,
            minute: 45,
            timeZone: london
        )

        let stored = ZuluDateEditing.storedValue(
            from: pickerValue,
            preserving: original,
            component: .date,
            in: london
        )

        #expect(stored == (try isoDate("2026-08-13T09:05:37Z")))
    }

    private func isoDate(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    private func localDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        timeZone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try #require(calendar.date(from: components))
    }
}
