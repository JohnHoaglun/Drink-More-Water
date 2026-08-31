import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import AVFoundation
import AudioToolbox

// MARK: - Notification Sound Player

/// Manages in-foreground notification audio so we can stop it immediately when the user responds.
/// The system's `.sound` presentation option cannot be cancelled once playing, so foreground
/// delivery skips `.sound` in the presentation options and delegates to this player instead.
final class NotificationSoundPlayer: NSObject, @unchecked Sendable {
    static let shared = NotificationSoundPlayer()
    private var player: AVAudioPlayer?

    func play(_ soundName: String) {
        stop()

        if soundName == "default" || soundName.isEmpty {
            Log.info("Playing system sound (default) via AudioServices", category: .sound)
            AudioServicesPlaySystemSound(1007)
            return
        }

        let base = (soundName as NSString).deletingPathExtension
        let ext  = (soundName as NSString).pathExtension

        guard let url = Bundle.main.url(forResource: base, withExtension: ext) else {
            Log.warn("Sound file not found in bundle: '\(soundName)' — falling back to system sound", category: .sound)
            AudioServicesPlaySystemSound(1007)
            return
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.play()
            player = p
            Log.info("AVAudioPlayer started: \(soundName)", category: .sound)
        } catch {
            Log.error("AVAudioPlayer failed for '\(soundName)': \(error) — falling back to system sound", category: .sound)
            AudioServicesPlaySystemSound(1007)
        }
    }

    func stop() {
        guard let p = player, p.isPlaying else { return }
        p.stop()
        player = nil
        Log.info("AVAudioPlayer stopped", category: .sound)
    }

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }
}

@main
struct Drink_More_WaterApp: App {
    private let modelContainer: ModelContainer

    init() {
        Log.setup()

        // cloudKitDatabase: .none prevents SwiftData from automatically enabling CloudKit
        // sync when iCloud container entitlements are present. We use iCloud only for
        // the log file (iCloud Documents), not for data sync.
        let storeConfig = ModelConfiguration(cloudKitDatabase: .none)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: ReminderEvent.self, AppSettings.self,
                                           configurations: storeConfig)
        } catch {
            let storeURL = storeConfig.url
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension())
            do {
                container = try ModelContainer(for: ReminderEvent.self, AppSettings.self,
                                               configurations: storeConfig)
            } catch {
                Log.error("SwiftData store recovery failed: \(error)")
                fatalError("Cannot load SwiftData store after recovery attempt.")
            }
        }
        modelContainer = container

        NotificationDelegate.shared.modelContainer = container
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Constants.bgTaskID,
            using: nil
        ) { task in
            guard let bgTask = task as? BGAppRefreshTask else { return }
            AppBackground.refresh(task: bgTask)
        }

        Task { @MainActor in
            await NotificationScheduler.requestAuthorization()
        }

        Log.warn(
            "[LAUNCH] \(Constants.buildTag) " +
            "hasUDBackup=\(AppSettingsBackup.hasBackup) " +
            "debugLog=\(UserDefaults.standard.bool(forKey: "AppSettings.isDebugLoggingEnabled")) " +
            "firstTopUp=\(String(describing: UserDefaults.standard.object(forKey: "DMW.firstTopUpTimeThisInstall") as? Date)) " +
            "lastClear=\(String(describing: UserDefaults.standard.object(forKey: "DMW.lastHistoryClear") as? Date))",
            category: .app
        )
        NotificationScheduler.logNotificationCenterSnapshot(reason: "launch")
    }

    var body: some Scene {
        WindowGroup {
            RootView(modelContainer: modelContainer)
                .modelContainer(modelContainer)
        }
    }
}

// MARK: - Notification delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()
    var modelContainer: ModelContainer?

    /// Called when a notification arrives while the app is in the FOREGROUND.
    /// We handle sound ourselves (so we can stop it on response) and return only .banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let content   = notification.request.content
        let soundName = content.userInfo["soundName"] as? String ?? "default"
        let isAudible = content.userInfo["isAudible"] as? Bool ?? true

        Log.info(
            "Notification will present (FOREGROUND) — id=\(notification.request.identifier), " +
            "sound=\(soundName), audible=\(isAudible), deliveredAt=\(notification.date.formatted(date: .omitted, time: .standard))",
            category: .notification
        )

        if isAudible {
            // Play via in-app player so we can stop it the moment the user responds.
            // Returning [.banner] (without .sound) prevents the system from also playing it.
            NotificationSoundPlayer.shared.play(soundName)
        } else {
            Log.info("Sound suppressed — isAudible=false", category: .sound)
        }

        // .banner shows the notification overlay. No .sound here — in-app player handles audio.
        return [.banner]
    }

    /// Called when the user taps an action button (Drink / Ignore) or the banner itself.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let deliveredAt     = response.notification.date
        let respondedAt     = Date()
        let responseLatency = respondedAt.timeIntervalSince(deliveredAt)

        Log.info(
            "Notification response — id=\(response.notification.request.identifier), " +
            "action=\(response.actionIdentifier), " +
            "responseLatency=\(String(format: "%.1f", responseLatency))s",
            category: .interaction
        )

        NotificationSoundPlayer.shared.stop()

        let store = HydrationEventStore(modelContainer: modelContainer)
        guard let settings = store.fetchOrCreateSettings() else {
            Log.warn("didReceive: could not load settings", category: .notification)
            return
        }
        guard settings.hasCompletedSetup else {
            Log.warn("didReceive: setup not complete — ignoring response", category: .notification)
            return
        }

        let responseToRecord: ResponseType? = switch response.actionIdentifier {
        case NotificationActions.drink:  .drink
        case NotificationActions.ignore: .ignore
        default: nil
        }

        guard let responseToRecord else {
            Log.info("didReceive: default banner tap — no action recorded", category: .interaction)
            return
        }

        Log.info(
            "Recording notification action: \(responseToRecord) — latency=\(String(format: "%.1f", responseLatency))s",
            category: .interaction
        )

        if await store.hasEvents() {
            await store.backfillMissed(settings: settings, lookback: .hours(24))
        }

        if let slot = SchedulingCalculator.slotTime(from: response.notification.request.identifier) {
            // slotTime returns the +120s notification-adjusted time. Store at the original
            // unshifted time so activeSlot's recorded-set logic correctly matches it.
            let originalSlot = slot.addingTimeInterval(-120)
            Log.info("Recording event from notification: slot=\(originalSlot.formatted(date: .omitted, time: .standard)), response=\(responseToRecord)", category: .event)
            await store.record(.init(scheduledAt: originalSlot, response: responseToRecord,
                                     personName: settings.personName))
        } else {
            Log.warn("Could not parse slot time from notification id: \(response.notification.request.identifier)", category: .notification)
        }
        NotificationScheduler(modelContainer: modelContainer).topUp(settings: settings)
    }
}

// MARK: - Background refresh

enum AppBackground {
    static func refresh(task: BGAppRefreshTask) {
        Log.info("Background refresh started", category: .app)
        let work = Task {
            do {
                let container = try ModelContainer(
                    for: ReminderEvent.self, AppSettings.self
                )
                let store = HydrationEventStore(modelContainer: container)

                if let settings = store.fetchOrCreateSettings() {
                    if await store.hasEvents() {
                        await store.backfillMissed(settings: settings, lookback: .hours(24))
                    }
                    NotificationScheduler(modelContainer: container).topUp(settings: settings)
                    Log.info("Background refresh complete", category: .app)
                }
            } catch {
                Log.error("Background refresh failed: \(error)", category: .app)
            }
        }
        task.expirationHandler = {
            work.cancel()
            Log.warn("Background refresh expired before completion", category: .app)
        }
    }
}
