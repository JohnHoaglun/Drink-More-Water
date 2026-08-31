import Foundation

/// One period's counts. `id` is the bucket start date.
struct StatsBucket: Identifiable {
    let id: Date
    let label: String
    var drink = 0
    var ignore = 0
    var missed = 0
}

/// Pure rollups from `ReminderEvent` rows. No I/O, easy to unit-test.
/// Buckets always use the device's current local calendar (spec: no fixed timezone).
enum StatsAggregator {
    enum Granularity: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    static func buckets(
        for events: [ReminderEvent],
        granularity: Granularity,
        bucketCount: Int,
        now: Date = Date()
    ) -> [StatsBucket] {
        let calendar = Calendar.current

        // Anchors: the start of each trailing bucket, oldest first.
        var anchors: [Date] = []
        for offset in stride(from: bucketCount - 1, through: 0, by: -1) {
            let key = bucketStart(for: now, goingBack: offset, granularity: granularity, calendar: calendar)
            if let key { anchors.append(key) }
        }

        var buckets: [Date: StatsBucket] = [:]
        for anchor in anchors {
            buckets[anchor] = StatsBucket(id: anchor, label: label(for: anchor, granularity: granularity))
        }

        // Assign each event into the bucket containing it.
        for event in events {
            let key = bucketStart(for: event.scheduledAt, goingBack: 0, granularity: granularity, calendar: calendar)
            guard let key, var bucket = buckets[key] else { continue }
            switch event.response {
            case .drink:  bucket.drink += 1
            case .ignore: bucket.ignore += 1
            case .missed: bucket.missed += 1
            }
            buckets[key] = bucket
        }

        return anchors.compactMap { buckets[$0] }
    }

    // MARK: -

    /// Start of the bucket that contains `date`, `offset` buckets in the past.
    private static func bucketStart(
        for date: Date,
        goingBack offset: Int,
        granularity: Granularity,
        calendar: Calendar
    ) -> Date? {
        switch granularity {
        case .day:
            let day = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .day, value: -offset, to: day)
        case .week:
            let shifted = calendar.date(byAdding: .weekOfYear, value: -offset, to: date) ?? date
            return calendar.dateInterval(of: .weekOfYear, for: shifted)?.start
        case .month:
            let shifted = calendar.date(byAdding: .month, value: -offset, to: date) ?? date
            return calendar.dateInterval(of: .month, for: shifted)?.start
        }
    }

    private static func label(for bucketStart: Date, granularity: Granularity) -> String {
        switch granularity {
        case .day:
            return bucketStart.formatted(.dateTime.weekday(.abbreviated))
        case .week:
            return bucketStart.formatted(.dateTime.month(.abbreviated).day())
        case .month:
            return bucketStart.formatted(.dateTime.month(.abbreviated).year())
        }
    }
}
