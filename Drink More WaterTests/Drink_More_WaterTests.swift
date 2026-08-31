import Foundation
import Testing
@testable import Drink_More_Water

struct SchedulingCalculatorTests {
    @Test func slotsIncludeStartAndExactEnd() {
        let settings = AppSettings(startHour: 8, startMinute: 0, endHour: 9, endMinute: 0, intervalMinutes: 30)
        let slots = SchedulingCalculator.slots(on: date(year: 2026, month: 8, day: 30), settings: settings)

        #expect(slots.map(time) == ["08:00", "08:30", "09:00"])
    }

    @Test func slotsStopBeforeNonExactEnd() {
        let settings = AppSettings(startHour: 8, startMinute: 0, endHour: 9, endMinute: 10, intervalMinutes: 30)
        let slots = SchedulingCalculator.slots(on: date(year: 2026, month: 8, day: 30), settings: settings)

        #expect(slots.map(time) == ["08:00", "08:30", "09:00"])
    }

    @Test func invalidIntervalReturnsNoSlots() {
        let settings = AppSettings(intervalMinutes: 0)

        #expect(SchedulingCalculator.slots(on: Date(), settings: settings).isEmpty)
    }

    @Test func rangeSlotsFilterAcrossDays() {
        let settings = AppSettings(startHour: 23, startMinute: 0, endHour: 23, endMinute: 30, intervalMinutes: 30)
        let start = date(year: 2026, month: 8, day: 30, hour: 23, minute: 15)
        let end = date(year: 2026, month: 8, day: 31, hour: 23, minute: 15)

        let slots = SchedulingCalculator.slots(from: start, to: end, settings: settings)

        #expect(slots.map(dayAndTime) == ["08-30 23:30", "08-31 23:00"])
    }

    @Test func identifierRoundTripsSlotTime() throws {
        let slot = date(year: 2026, month: 8, day: 30, hour: 8, minute: 15, second: 10)
        let decoded = try #require(SchedulingCalculator.slotTime(from: SchedulingCalculator.identifier(for: slot)))

        #expect(abs(decoded.timeIntervalSince(slot)) < 0.001)
    }
}

struct StatsAggregatorTests {
    @Test func emptyEventsReturnEmptyCountBuckets() {
        let now = date(year: 2026, month: 8, day: 30, hour: 12)

        let buckets = StatsAggregator.buckets(for: [], granularity: .day, bucketCount: 2, now: now)

        #expect(buckets.count == 2)
        #expect(buckets.allSatisfy { $0.drink == 0 && $0.ignore == 0 && $0.missed == 0 })
    }

    @Test func mixedResponsesCountInCurrentDay() {
        let now = date(year: 2026, month: 8, day: 30, hour: 12)
        let events = [
            ReminderEvent(scheduledAt: date(year: 2026, month: 8, day: 30, hour: 8), response: .drink),
            ReminderEvent(scheduledAt: date(year: 2026, month: 8, day: 30, hour: 9), response: .ignore),
            ReminderEvent(scheduledAt: date(year: 2026, month: 8, day: 30, hour: 10), response: .missed)
        ]

        let bucket = StatsAggregator.buckets(for: events, granularity: .day, bucketCount: 1, now: now)[0]

        #expect(bucket.drink == 1)
        #expect(bucket.ignore == 1)
        #expect(bucket.missed == 1)
    }

    @Test func oldEventsOutsideTrailingWindowAreIgnored() {
        let now = date(year: 2026, month: 8, day: 30, hour: 12)
        let events = [
            ReminderEvent(scheduledAt: date(year: 2026, month: 8, day: 29, hour: 8), response: .drink),
            ReminderEvent(scheduledAt: date(year: 2026, month: 8, day: 30, hour: 8), response: .ignore)
        ]

        let bucket = StatsAggregator.buckets(for: events, granularity: .day, bucketCount: 1, now: now)[0]

        #expect(bucket.drink == 0)
        #expect(bucket.ignore == 1)
        #expect(bucket.missed == 0)
    }

    @Test func weekAndMonthBucketsCountMatchingEvents() {
        let now = date(year: 2026, month: 8, day: 30, hour: 12)
        let events = [
            ReminderEvent(scheduledAt: date(year: 2026, month: 8, day: 30, hour: 8), response: .drink),
            ReminderEvent(scheduledAt: date(year: 2026, month: 8, day: 15, hour: 8), response: .missed)
        ]

        let week = StatsAggregator.buckets(for: events, granularity: .week, bucketCount: 1, now: now)[0]
        let month = StatsAggregator.buckets(for: events, granularity: .month, bucketCount: 1, now: now)[0]

        #expect(week.drink == 1)
        #expect(month.drink == 1)
        #expect(month.missed == 1)
    }
}

struct CSVExporterTests {
    @Test func emptyExportReturnsHeaderOnly() {
        #expect(CSVExporter.csv(for: []) == "scheduled_at,response,person")
    }

    @Test func rowsAreSortedByScheduledDate() {
        let later = ReminderEvent(scheduledAt: date(year: 2026, month: 8, day: 30, hour: 9), response: .ignore, personName: "Later")
        let earlier = ReminderEvent(scheduledAt: date(year: 2026, month: 8, day: 30, hour: 8), response: .drink, personName: "Earlier")

        let lines = CSVExporter.csv(for: [later, earlier]).components(separatedBy: "\n")

        #expect(lines[1].contains(",drink,Earlier"))
        #expect(lines[2].contains(",ignore,Later"))
    }

    @Test func personNamesEscapeCsvSpecialCharacters() {
        let event = ReminderEvent(
            scheduledAt: date(year: 2026, month: 8, day: 30, hour: 8),
            response: .drink,
            personName: "John \"JH\", Sr."
        )

        let line = CSVExporter.csv(for: [event]).components(separatedBy: "\n")[1]

        #expect(line.hasSuffix(",drink,\"John \"\"JH\"\", Sr.\""))
    }
}

private func date(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0,
    second: Int = 0
) -> Date {
    Calendar.current.date(from: DateComponents(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second
    ))!
}

private func time(_ date: Date) -> String {
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", components.hour!, components.minute!)
}

private func dayAndTime(_ date: Date) -> String {
    let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
    return String(
        format: "%02d-%02d %02d:%02d",
        components.month!,
        components.day!,
        components.hour!,
        components.minute!
    )
}
