import Foundation
import SwiftData

/// Read/write access to hydration data.
final class HydrationEventStore: @unchecked Sendable {

    private let modelContainer: ModelContainer?

    init(modelContainer: ModelContainer?) {
        self.modelContainer = modelContainer
    }

    // MARK: Settings

    func fetchOrCreateSettings() -> AppSettings? {
        guard let modelContainer else { return nil }
        let context = ModelContext(modelContainer)

        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let settings = AppSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    // MARK: Missed backfill

    /// Marks unrecorded past slots as `.missed`.
    ///
    /// - Parameters:
    ///   - settings: the active schedule.
    ///   - lookback: how far back to search (e.g. 24 h).
    ///   - forceAll: when `true`, every slot before *now* is treated as
    ///     expired (not just those older than one interval). Use this on
    ///     first save / schedule change so stale slots don't trigger the
    ///     Drink/Ignore buttons.
    func backfillMissed(settings: AppSettings, lookback: Duration, forceAll: Bool = false) async {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)

        let now = Date()
        let lookbackStart = now.addingTimeInterval(-seconds(from: lookback))

        // forceAll → boundary is "now" (everything before now is missed).
        // Normal   → boundary is "now − one interval" (only stale slots).
        let expiredBefore = forceAll
            ? now
            : now.addingTimeInterval(-TimeInterval(max(settings.intervalMinutes, 1) * 60))

        let searchStart = lookbackStart
        guard searchStart < expiredBefore else { return }

        let predicate = #Predicate<ReminderEvent> { $0.scheduledAt >= searchStart && $0.scheduledAt < expiredBefore }
        let existing = (try? context.fetch(FetchDescriptor<ReminderEvent>(predicate: predicate))) ?? []
        let recordedSlots = Set(existing.map { $0.scheduledAt })

        for slot in SchedulingCalculator.slots(from: searchStart, to: expiredBefore, settings: settings)
        where !recordedSlots.contains(slot) {
            context.insert(ReminderEvent(scheduledAt: slot, response: .missed,
                                         personName: settings.personName))
        }

        try? context.save()
        await Task.yield()
    }

    // MARK: Recording responses

    func record(_ event: ReminderEvent) async {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        context.insert(event)
        try? context.save()
        await Task.yield()
    }

    // MARK: Clearing history

    func clearAllHistory() async {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        let all = (try? context.fetch(FetchDescriptor<ReminderEvent>())) ?? []
        all.forEach { context.delete($0) }
        try? context.save()
        await Task.yield()
    }

    // MARK: -

    private func seconds(from duration: Duration) -> TimeInterval {
        let c = duration.components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1e18
    }
}
