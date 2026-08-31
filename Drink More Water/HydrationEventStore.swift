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
        if AppSettingsBackup.hasBackup {
            AppSettingsBackup.restore(into: settings)
            Log.warn("Store was empty — restored settings from UserDefaults backup", category: .settings)
        } else {
            Log.info("Created new AppSettings (first launch)", category: .settings)
        }
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
        let newName  = baseName + ".caf"

        let url = Bundle.main.url(forResource: newName, withExtension: "")
        guard url != nil else {
            Log.warn("Sound migration: '\(settings.soundName)' → no .caf found, resetting to default", category: .settings)
            settings.soundName = "default"
            try? context.save()
            return
        }

        Log.info("Sound migration: '\(settings.soundName)' → '\(newName)'", category: .settings)
        settings.soundName = newName
        try? context.save()
    }

    // MARK: Missed backfill

    /// Marks unrecorded past slots as `.missed`.
    func backfillMissed(settings: AppSettings, lookback: Duration, forceAll: Bool = false) async {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)

        let now = Date()
        // Never backfill before the most recent of: app setup, last history clear.
        // This prevents fake data after the user intentionally resets history.
        let lastClear = UserDefaults.standard.object(forKey: "DMW.lastHistoryClear") as? Date
        let anchor = max(settings.createdAt, lastClear ?? .distantPast)
        let lookbackStart = max(
            now.addingTimeInterval(-seconds(from: lookback)),
            anchor
        )

        let expiredBefore = forceAll
            ? now
            : now.addingTimeInterval(-TimeInterval(max(settings.intervalMinutes, 1) * 60))

        let searchStart = lookbackStart
        guard searchStart < expiredBefore else { return }

        let start = searchStart
        let end   = expiredBefore
        let predicate = #Predicate<ReminderEvent> { $0.scheduledAt >= start && $0.scheduledAt < end }
        let existing = (try? context.fetch(FetchDescriptor<ReminderEvent>(predicate: predicate))) ?? []
        let recordedSlots = Set(existing.map { $0.scheduledAt })

        var missedCount = 0
        for slot in SchedulingCalculator.slots(from: searchStart, to: expiredBefore, settings: settings) {
            if recordedSlots.contains(slot) { continue }
            context.insert(ReminderEvent(scheduledAt: slot, response: .missed, personName: settings.personName))
            missedCount += 1
        }

        if missedCount > 0 {
            Log.info("Backfilled \(missedCount) missed slot(s) in [lookback=\(Int(seconds(from: lookback)))s]", category: .event)
        }

        try? context.save()
        await Task.yield()
    }

    // MARK: Auto-ignore expired slots

    /// Records unresponded slots older than `window` seconds as `.ignore`.
    /// This is the 2-minute expiry: if the user didn't tap within the window,
    /// the slot is counted as ignored and buttons disappear.
    func autoIgnoreExpired(settings: AppSettings, window: TimeInterval) async {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)

        let now     = Date()
        let cutoff  = now.addingTimeInterval(-window)
        let lastClear = UserDefaults.standard.object(forKey: "DMW.lastHistoryClear") as? Date
        let anchor = max(settings.createdAt, lastClear ?? .distantPast)
        let lookback = max(now.addingTimeInterval(-seconds(from: .hours(1))), anchor)

        let start = lookback
        let end   = cutoff
        let predicate = #Predicate<ReminderEvent> { $0.scheduledAt >= start && $0.scheduledAt < end }
        let recent = (try? context.fetch(FetchDescriptor<ReminderEvent>(predicate: predicate))) ?? []
        let recordedSlots = Set(recent.map { $0.scheduledAt })

        var ignoredCount = 0
        for slot in SchedulingCalculator.slots(from: lookback, to: cutoff, settings: settings) {
            if recordedSlots.contains(slot) { continue }
            Log.info(
                "Auto-ignoring expired slot: \(slot.formatted(date: .omitted, time: .standard)) (older than \(Int(window))s window)",
                category: .event
            )
            context.insert(ReminderEvent(scheduledAt: slot, response: .ignore, personName: settings.personName))
            ignoredCount += 1
        }

        if ignoredCount > 0 {
            Log.info("Auto-ignored \(ignoredCount) expired slot(s)", category: .event)
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

        let scheduledAt = event.scheduledAt
        let predicate = #Predicate<ReminderEvent> { $0.scheduledAt == scheduledAt }
        let existing = (try? context.fetch(FetchDescriptor<ReminderEvent>(predicate: predicate))) ?? []
        if !existing.isEmpty {
            Log.debug("Duplicate event ignored: slot=\(scheduledAt.formatted(date: .omitted, time: .standard)), response=\(event.response)", category: .event)
            return
        }

        Log.info("Recording event: slot=\(scheduledAt.formatted(date: .omitted, time: .standard)), response=\(event.response), person=\(event.personName)", category: .event)
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
        UserDefaults.standard.set(Date(), forKey: "DMW.lastHistoryClear")
        Log.info("Cleared all history (\(all.count) records)", category: .event)
        await Task.yield()
    }

    // MARK: -

    private func seconds(from duration: Duration) -> TimeInterval {
        let c = duration.components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1e18
    }
}
