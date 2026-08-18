import Foundation

/// Pure date math for reminder slots. No I/O, easy to unit-test.
enum SchedulingCalculator {

    // MARK: Slot time ↔ notification identifier

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Notification request identifier for a slot (unique per slot).
    static func identifier(for slot: Date) -> String {
        isoFormatter.string(from: slot)
    }

    /// Slot time encoded in a notification request identifier.
    static func slotTime(from identifier: String) -> Date? {
        isoFormatter.date(from: identifier)
    }

    // MARK: Slot generation

    /// All reminder slots on the given day: `startHour:startMinute` through
    /// `endHour:endMinute` at `intervalMinutes` spacing.
    static func slots(on day: Date, settings: AppSettings) -> [Date] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        guard settings.intervalMinutes > 0,
              let start = calendar.date(from: DateComponents(
                  year: components.year, month: components.month, day: components.day,
                  hour: settings.startHour, minute: settings.startMinute
              )),
              let end = calendar.date(from: DateComponents(
                  year: components.year, month: components.month, day: components.day,
                  hour: settings.endHour, minute: settings.endMinute
              )),
              start < end
        else {
            return []
        }

        let step = TimeInterval(settings.intervalMinutes * 60)
        var slots: [Date] = []
        var slot = start
        while slot <= end {
            slots.append(slot)
            slot.addTimeInterval(step)
        }
        return slots
    }

    /// Slots falling within [start, end] — used by backfill and reschedule.
    static func slots(from start: Date, to end: Date, settings: AppSettings) -> [Date] {
        let calendar = Calendar.current
        var result: [Date] = []
        var day = calendar.startOfDay(for: min(start, end))
        let lastDay = calendar.startOfDay(for: max(start, end))
        while day <= lastDay {
            result += slots(on: day, settings: settings).filter { $0 >= start && $0 <= end }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? .distantFuture
        }
        return result
    }
}
