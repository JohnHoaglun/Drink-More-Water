import Foundation
import UserNotifications
import SwiftData
import UIKit

/// Cancels and re-registers local notifications for upcoming reminder slots.
struct NotificationScheduler {
    static let categoryID = "HYDRATION_REMINDER"

    /// iOS enforces a hard cap of 64 pending notification requests per app.
    static let maxPending = 64

    private static var _delegateRetainer: UNUserNotificationCenterDelegate?

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
        Self.installNotificationHandling()
    }

    /// Full wipe-and-rebuild. Use ONLY when the schedule has fundamentally
    /// changed (settings saved).
    func reschedule(settings: AppSettings) {
        Self.installNotificationHandling()
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
        Self.installNotificationHandling()
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
        }

        content.threadIdentifier = Self.categoryID
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [
            "soundName": settings.soundName,
            "isAudible": settings.isAudible
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

        // Normalize the incoming name: allow either base name or full filename.
        let candidateNames: [String]
        if name.contains(".") {
            candidateNames = [name]
        } else {
            candidateNames = ["\(name).caf", name]
        }

        // Search for a matching resource in the main bundle.
        for candidate in candidateNames {
            if let _ = Bundle.main.url(forResource: candidate, withExtension: nil) {
                #if DEBUG
                print("[NotificationScheduler] Using custom sound: \(candidate)")
                #endif
                return UNNotificationSound(named: UNNotificationSoundName(candidate))
            }
        }

        // As a final fallback, try common audio extensions just in case.
        let commonExtensions = ["caf", "aiff", "wav"]
        for ext in commonExtensions {
            if let _ = Bundle.main.url(forResource: name, withExtension: ext) {
                let resolved = "\(name).\(ext)"
                #if DEBUG
                print("[NotificationScheduler] Using custom sound: \(resolved)")
                #endif
                return UNNotificationSound(named: UNNotificationSoundName(resolved))
            }
        }

        #if DEBUG
        print("[NotificationScheduler] Custom sound not found for name: \(name). Falling back to default.")
        #endif
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

    /// Installs a foreground presentation delegate so notifications can show banner + sound while app is active.
    static func installNotificationHandling() {
        let center = UNUserNotificationCenter.current()
        // Ensure categories are registered early
        let scheduler = NotificationScheduler(modelContainer: nil)
        scheduler.registerActions()
        if center.delegate == nil {
            class ForegroundDelegate: NSObject, UNUserNotificationCenterDelegate {
                func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
                    completionHandler([.banner, .sound])
                }
            }
            let delegate = ForegroundDelegate()
            center.delegate = delegate
            Self._delegateRetainer = delegate
        }
    }
}
