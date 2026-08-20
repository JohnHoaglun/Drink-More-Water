import Foundation
import UserNotifications
import SwiftData

/// Cancels and re-registers local notifications for upcoming reminder slots.
struct NotificationScheduler {
    static let categoryID = "HYDRATION_REMINDER"

    /// iOS enforces a hard cap of 64 pending notification requests per app.
    static let maxPending = 64

    private let modelContainer: ModelContainer?

    init(modelContainer: ModelContainer?) {
        self.modelContainer = modelContainer
    }

    @MainActor
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Full wipe-and-rebuild. Use ONLY when the schedule has fundamentally
    /// changed (settings saved).
    func reschedule(settings: AppSettings) {
        registerActions()

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let now = Date()
        let horizon = now.addingTimeInterval(24 * 3600)

        var recordedSlots: Set<Date> = []
        if let modelContainer {
            let context = ModelContext(modelContainer)
            let predicate = #Predicate<ReminderEvent> { $0.scheduledAt >= now }
            let future = (try? context.fetch(FetchDescriptor<ReminderEvent>(predicate: predicate))) ?? []
            recordedSlots = Set(future.map { $0.scheduledAt })
        }

        var added = 0
        for slot in SchedulingCalculator.slots(from: now, to: horizon, settings: settings) {
            guard added < Self.maxPending else { break }
            guard !recordedSlots.contains(slot) else { continue }
            center.add(buildRequest(for: slot, settings: settings))
            added += 1
        }
    }

    /// Top-up: add only the slots that aren't already pending.
    /// Does NOT wipe existing notifications.
    func topUp(settings: AppSettings) {
        let center = UNUserNotificationCenter.current()

        let now = Date()
        let horizon = now.addingTimeInterval(24 * 3600)

        var recordedSlots: Set<Date> = []
        if let modelContainer {
            let context = ModelContext(modelContainer)
            let predicate = #Predicate<ReminderEvent> { $0.scheduledAt >= now }
            let future = (try? context.fetch(FetchDescriptor<ReminderEvent>(predicate: predicate))) ?? []
            recordedSlots = Set(future.map { $0.scheduledAt })
        }

        let candidateSlots = SchedulingCalculator.slots(from: now, to: horizon, settings: settings)
            .filter { !recordedSlots.contains($0) }
            .prefix(Self.maxPending)
            .map { SchedulingCalculator.identifier(for: $0) }
            .reduce(into: Set<String>()) { $0.insert($1) }

        var alreadyPending: Set<String> = []
        let semaphore = DispatchSemaphore(value: 0)
        center.getPendingNotificationRequests { requests in
            alreadyPending = Set(requests.map { $0.identifier })
            semaphore.signal()
        }
        semaphore.wait()

        for slot in SchedulingCalculator.slots(from: now, to: horizon, settings: settings)
        where !recordedSlots.contains(slot) {
            let id = SchedulingCalculator.identifier(for: slot)
            guard candidateSlots.contains(id) else { continue }
            guard !alreadyPending.contains(id) else { continue }
            center.add(buildRequest(for: slot, settings: settings))
        }
    }

    // MARK: -

    /// Builds a `UNNotificationRequest` for a given slot.
    private func buildRequest(for slot: Date, settings: AppSettings) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Time to drink water 💧"
        content.body = "Your next glass is scheduled for \(slot.formatted(date: .omitted, time: .shortened))."
        if settings.isAudible {
            content.sound = Self.notificationSound(for: settings.soundName)
        } else {
            content.sound = nil
        }
        content.threadIdentifier = Self.categoryID
        content.categoryIdentifier = Self.categoryID

        // Store the sound name so `willPresent` can play it via our
        // AVAudioPlayer (which we can stop). The system won't play it
        // in-foreground because we omit `.sound` from presentation options.
        content.userInfo = [
            "soundName": settings.isAudible ? settings.soundName : ""
        ]

        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: slot
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        return UNNotificationRequest(
            identifier: SchedulingCalculator.identifier(for: slot),
            content: content,
            trigger: trigger
        )
    }

    /// Resolves the notification sound from the stored `soundName`.
    static func notificationSound(for name: String) -> UNNotificationSound {
        guard name != "default" else { return .default }
        if Bundle.main.url(forResource: (name as NSString).deletingPathExtension,
                           withExtension: (name as NSString).pathExtension) != nil {
            return UNNotificationSound(named: UNNotificationSoundName(name))
        }
        return .default
    }

    private func registerActions() {
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [
                UNNotificationAction(identifier: NotificationActions.drink,
                                     title: "Drank it",
                                     options: []),
                UNNotificationAction(identifier: NotificationActions.ignore,
                                     title: "Ignore",
                                     options: [])
            ],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
