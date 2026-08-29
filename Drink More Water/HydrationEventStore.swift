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
            migrateSoundName(context, existing)
            return existing
        }

        let settings = AppSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    // MARK: - Sound Migration

    /// Converts old .m4a/.mp3 sound names to their .caf equivalents.
    private func migrateSoundName(_ context: ModelContext, _ settings: AppSettings) {
        guard !["default", ""].contains(settings.soundName) else { return }
        
        let ext = (settings.soundName as NSString).pathExtension
        guard ext == "m4a" || ext == "mp3" else { return }
        
        let baseName = (settings.soundName as NSString).deletingPathExtension
        let newName = baseName + ".caf"
        
        // Check the new file exists in the bundle
        let url = Bundle.main.url(forResource: newName, withExtension: "")
        guard url != nil else {
            settings.soundName = "default"
            try? context.save()
            return
        }
        
        settings.soundName = newName
        try? context.save()
    }

    // MARK: Missed backfill

    /// Marks unrecorded past slots as `.missed`.
    ///
    /// - Parameters:
    ///   - settings: the active schedule.
    ///   - lookback: how far back to search (e.g. 24 h).
    ///   - forceAll: when `true`, every slot before *now* is treated as
    ///     expired (not just those older than one interval).
    func backfillMissed(settings: AppSettings, lookback: Duration, forceAll: Bool = false) async {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)

        let now = Date()
        let lookbackStart = now.addingTimeInterval(-seconds(from: lookback))

        let expiredBefore = forceAll
            ? now
            : now.addingTimeInterval(-TimeInterval(max(settings.intervalMinutes, 1) * 60))

        let searchStart = lookbackStart
        guard searchStart < expiredBefore else { return }

        let start = searchStart
        let end = expiredBefore
        let predicate = #Predicate<ReminderEvent> { $0.scheduledAt >= start && $0.scheduledAt < end }
        let existing = (try? context.fetch(FetchDescriptor<ReminderEvent>(predicate: predicate))) ?? []
        let recordedSlots = Set(existing.map { $0.scheduledAt })

        for slot in SchedulingCalculator.slots(from: searchStart, to: expiredBefore, settings: settings) {
            if recordedSlots.contains(slot) {
                continue
            }
            context.insert(ReminderEvent(scheduledAt: slot, response: .missed,
                                         personName: settings.personName))
        }

        try? context.save()
        await Task.yield()
    }

    // MARK: Auto-ignore expired slots

    /// Records unresponded slots that are older than `window` seconds
    /// as `.ignore`. This is the 90-second expiry: if the user didn't
    /// tap Drink or Ignore (on the notification or in-app) within the
    /// window, the slot is counted as ignored and buttons disappear.
    func autoIgnoreExpired(settings: AppSettings, window: TimeInterval) async {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)

        let now = Date()
        let cutoff = now.addingTimeInterval(-window)
        let lookback = now.addingTimeInterval(-seconds(from: .hours(1)))

        let start = lookback
        let end = cutoff
        let predicate = #Predicate<ReminderEvent> { $0.scheduledAt >= start && $0.scheduledAt < end }
        let recent = (try? context.fetch(FetchDescriptor<ReminderEvent>(predicate: predicate))) ?? []
        let recordedSlots = Set(recent.map { $0.scheduledAt })

        for slot in SchedulingCalculator.slots(from: lookback, to: cutoff, settings: settings) {
            if recordedSlots.contains(slot) {
                continue
            }
            context.insert(ReminderEvent(scheduledAt: slot, response: .ignore,
                                         personName: settings.personName))
        }

        try? context.save()
        await Task.yield()
    }

    // MARK: Recording responses

    func hasEvents() async -> Bool {
        guard let modelContainer else { return false }
        let context = ModelContext(modelContainer)
        var desc = FetchDescriptor<ReminderEvent>()
        desc.fetchLimit = 1
        do {
            return try context.fetch(desc).first != nil
        } catch {
            return false
        }
    }

    func record(_ event: ReminderEvent) async {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        
        // Check for duplicate ReminderEvent with same scheduledAt
        let scheduledAt = event.scheduledAt
        let predicate = #Predicate<ReminderEvent> { $0.scheduledAt == scheduledAt }
        let existing = (try? context.fetch(FetchDescriptor<ReminderEvent>(predicate: predicate))) ?? []
        if !existing.isEmpty {
            return
        }
        
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
