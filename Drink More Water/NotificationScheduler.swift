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

    func reschedule(settings: AppSettings) {
        registerActions()

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let now = Date()
        let horizon = now.addingTimeInterval(24 * 3600)
        let calendar = Calendar.current

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

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: slot
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(
                identifier: SchedulingCalculator.identifier(for: slot),
                content: content,
                trigger: trigger
            )
            center.add(request)
            added += 1
        }
    }

    // MARK: -

    /// Resolves the notification sound from the stored `soundName`.
    ///
    /// `soundName` is either `"default"` or a filename like `"tone-bell.m4a"`.
    /// Bundled files are played via `UNNotificationSound(named:)`; anything
    /// not found falls back to the system default.
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
