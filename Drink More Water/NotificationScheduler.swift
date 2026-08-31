// NotificationScheduler.swift

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
        guard settings.authorizationStatus == .notDetermined else {
            Log.info("Notification auth status: \(settings.authorizationStatus.rawValue)", category: .notification)
            return
        }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        Log.info("Notification authorization requested — granted: \(granted)", category: .notification)
        Self.installNotificationHandling()
    }

    /// Full wipe-and-rebuild. Use ONLY when the schedule has fundamentally changed (settings saved).
    func reschedule(settings: AppSettings) {
        Log.info("Reschedule: full wipe-and-rebuild (sound=\(settings.soundName), audible=\(settings.isAudible))", category: .scheduler)
        Self.installNotificationHandling()
        registerActions()

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let now = Date()
        let horizon = now.addingTimeInterval(24 * 3600)

        var recordedSlots: Set<Date> = []
        if let modelContainer {
            let context = ModelContext(modelContainer)
            let normalizedNow = Calendar.current.date(bySetting: .second, value: 0, of: now) ?? now
            let predicate = #Predicate<ReminderEvent> { $0.scheduledAt >= normalizedNow }
            let future = (try? context.fetch(FetchDescriptor<ReminderEvent>(predicate: predicate))) ?? []
            recordedSlots = Set(future.map {
                Calendar.current.date(bySetting: .second, value: 0, of: $0.scheduledAt) ?? $0.scheduledAt
            })
        }

        var added = 0
        // Start from now-120 so base slots whose trigger time (+120s) is still in the future
        // are not skipped when reschedule runs just before a slot fires.
        for slot in SchedulingCalculator.slots(from: now.addingTimeInterval(-120), to: horizon, settings: settings).map({
            Calendar.current.date(bySetting: .second, value: 0, of: $0.addingTimeInterval(120)) ?? $0.addingTimeInterval(120)
        }).filter({ $0 > now }) {
            guard added < Self.maxPending else { break }
            guard !recordedSlots.contains(slot) else { continue }
            center.add(buildRequest(for: slot, settings: settings))
            added += 1
        }
        Log.info("Reschedule complete: scheduled \(added) notification(s) over next 24h", category: .scheduler)
        Self.logPendingNotifications(reason: "after reschedule", delay: 1)
    }

    /// Top-up: add only the slots that aren't already pending. Does NOT wipe existing notifications.
    func topUp(settings: AppSettings) {
        // Record the first time topUp runs this install. UserDefaults is cleared when
        // the app is deleted, so this timestamp resets on reinstall. MainView uses it
        // to prevent pre-install slots from appearing as overdue (fixes iCloud/backup restore).
        let installKey = "DMW.firstTopUpTimeThisInstall"
        if UserDefaults.standard.object(forKey: installKey) == nil {
            UserDefaults.standard.set(Date(), forKey: installKey)
            Log.warn("First topUp this install — recorded firstTopUpTimeThisInstall", category: .scheduler)
        }

        Log.debug("TopUp: checking for missing notification slots", category: .scheduler)
        Self.installNotificationHandling()
        let center = UNUserNotificationCenter.current()

        let now = Date()
        let horizon = now.addingTimeInterval(24 * 3600)

        var recordedSlots: Set<Date> = []
        if let modelContainer {
            let context = ModelContext(modelContainer)
            let normalizedNow = Calendar.current.date(bySetting: .second, value: 0, of: now) ?? now
            let predicate = #Predicate<ReminderEvent> { $0.scheduledAt >= normalizedNow }
            let future = (try? context.fetch(FetchDescriptor<ReminderEvent>(predicate: predicate))) ?? []
            recordedSlots = Set(future.map {
                Calendar.current.date(bySetting: .second, value: 0, of: $0.scheduledAt) ?? $0.scheduledAt
            })
        }

        let candidateSlots = SchedulingCalculator.slots(from: now.addingTimeInterval(-120), to: horizon, settings: settings)
            .map {
                Calendar.current.date(bySetting: .second, value: 0, of: $0.addingTimeInterval(120)) ?? $0.addingTimeInterval(120)
            }
            .filter { $0 > now }
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

        var added = 0
        for slot in SchedulingCalculator.slots(from: now.addingTimeInterval(-120), to: horizon, settings: settings).map({
            Calendar.current.date(bySetting: .second, value: 0, of: $0.addingTimeInterval(120)) ?? $0.addingTimeInterval(120)
        }).filter({ $0 > now })
        where !recordedSlots.contains(slot) {
            let id = SchedulingCalculator.identifier(for: slot)
            guard candidateSlots.contains(id) else { continue }
            guard !alreadyPending.contains(id) else { continue }
            center.add(buildRequest(for: slot, settings: settings))
            added += 1
        }

        Log.debug("TopUp complete: added \(added) notification(s), \(alreadyPending.count) already pending", category: .scheduler)
        Self.logPendingNotifications(reason: "after topUp", delay: 1)
    }

    // MARK: -

    /// Builds a `UNNotificationRequest` for a given slot.
    private func buildRequest(for slot: Date, settings: AppSettings) -> UNNotificationRequest {
        let preciseSlot = Calendar.current.date(bySetting: .second, value: 0, of: slot) ?? slot

        let content = UNMutableNotificationContent()
        content.title = "Time to drink water 💧"
        content.body = "Your next glass is scheduled for \(preciseSlot.formatted(date: .omitted, time: .shortened))."

        // Use the user's chosen custom sound (or nil when not audible).
        // Background/locked-screen delivery plays content.sound via the OS.
        // Foreground delivery is handled by NotificationSoundPlayer in willPresent.
        if settings.isAudible {
            let sound = Self.notificationSound(for: settings.soundName)
            content.sound = sound
            Log.info("buildRequest slot=\(preciseSlot.formatted(date: .omitted, time: .shortened)) sound=\(settings.soundName)", category: .sound)
        } else {
            content.sound = nil
            Log.info("buildRequest slot=\(preciseSlot.formatted(date: .omitted, time: .shortened)) sound=none (isAudible=false)", category: .sound)
        }

        content.threadIdentifier = Self.categoryID + "." + SchedulingCalculator.identifier(for: preciseSlot)
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [
            "soundName": settings.soundName,
            "isAudible": settings.isAudible,
            "scheduledAt": preciseSlot.timeIntervalSince1970
        ]

        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: preciseSlot
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        return UNNotificationRequest(
            identifier: SchedulingCalculator.identifier(for: preciseSlot),
            content: content,
            trigger: trigger
        )
    }

    /// Resolves the notification sound from the stored `soundName`.
    static func notificationSound(for name: String) -> UNNotificationSound {
        guard name != "default" else { return .default }

        let candidateNames: [String]
        if name.contains(".") {
            candidateNames = [name]
        } else {
            candidateNames = ["\(name).caf", name]
        }

        for candidate in candidateNames {
            if Bundle.main.url(forResource: candidate, withExtension: nil) != nil {
                Log.debug("Resolved notification sound: \(candidate)", category: .sound)
                return UNNotificationSound(named: UNNotificationSoundName(candidate))
            }
        }

        let commonExtensions = ["caf", "aiff", "wav"]
        for ext in commonExtensions {
            if Bundle.main.url(forResource: name, withExtension: ext) != nil {
                let resolved = "\(name).\(ext)"
                Log.debug("Resolved notification sound (by extension): \(resolved)", category: .sound)
                return UNNotificationSound(named: UNNotificationSoundName(resolved))
            }
        }

        Log.warn("Custom sound not found in bundle: '\(name)' — falling back to default", category: .sound)
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
        Log.debug("Notification category '\(Self.categoryID)' registered with drink/ignore actions", category: .notification)
    }

    /// Installs a foreground presentation delegate so notifications can show banner + sound while app is active.
    static func installNotificationHandling() {
        let center = UNUserNotificationCenter.current()
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
            Log.info("Installed fallback ForegroundDelegate", category: .notification)
        }
    }

    static func logNotificationCenterSnapshot(reason: String) {
        logPendingNotifications(reason: reason)
        logDeliveredNotifications(reason: reason)
    }

    private static func logPendingNotifications(reason: String, limit: Int = 10, delay: TimeInterval = 0) {
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                logPendingNotifications(reason: reason, limit: limit)
            }
            return
        }

        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ordered = requests.sorted {
                triggerDate(for: $0) ?? .distantFuture < triggerDate(for: $1) ?? .distantFuture
            }

            let sample = ordered.prefix(limit).map { request in
                let trigger = triggerDate(for: request)
                let triggerText = trigger?.formatted(date: .abbreviated, time: .standard) ?? "unknown"
                return "\(triggerText) id=\(request.identifier)"
            }.joined(separator: " | ")

            Log.warn(
                "[NOTIF SNAPSHOT] \(reason): pending=\(requests.count) first\(min(limit, ordered.count))=[\(sample)]",
                category: .notification
            )
        }
    }

    private static func logDeliveredNotifications(reason: String, limit: Int = 10) {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let ordered = notifications.sorted { $0.date > $1.date }
            let sample = ordered.prefix(limit).map { notification in
                "\(notification.date.formatted(date: .abbreviated, time: .standard)) id=\(notification.request.identifier)"
            }.joined(separator: " | ")

            Log.warn(
                "[NOTIF SNAPSHOT] \(reason): delivered=\(notifications.count) recent\(min(limit, ordered.count))=[\(sample)]",
                category: .notification
            )
        }
    }

    private static func triggerDate(for request: UNNotificationRequest) -> Date? {
        (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
    }
}
