import Foundation
import UserNotifications
import SwiftData

/// Cancels and re-registers local notifications for upcoming reminder slots.
struct NotificationScheduler {
    static let categoryID = "HYDRATION_REMINDER"

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

        for slot in SchedulingCalculator.slots(from: now.addingTimeInterval(60),
                                               to: horizon,
                                               settings: settings)
        where !alreadyRecorded(slot) {
            let content = UNMutableNotificationContent()
            content.title = "Time to drink water 💧"
            content.body = "Your next glass is scheduled for \(slot.formatted(date: .omitted, time: .shortened))."
            if settings.isAudible {
                if settings.soundName == "default" {
                    content.sound = .default
                } else {
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(settings.soundName))
                }
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
        }
    }

    // MARK: -

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

    /// Fixed: Uses a predicate to check existence instead of loading all history.
    private func alreadyRecorded(_ slot: Date) -> Bool {
        guard let modelContainer else { return false }
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<ReminderEvent> { $0.scheduledAt == slot }
        // Fixed: Wrapped predicate in FetchDescriptor to resolve type inference errors
        return (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0 > 0
    }
}
