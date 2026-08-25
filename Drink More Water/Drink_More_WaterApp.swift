import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import AVFoundation
import AudioToolbox

// MARK: - Notification Sound Player

/// Manages in-foreground notification audio so we can stop it
/// immediately when the user responds. The system's `.sound`
/// presentation option cannot be cancelled once playing.
final class NotificationSoundPlayer: NSObject, @unchecked Sendable {
    static let shared = NotificationSoundPlayer()
    private var player: AVAudioPlayer?

    func play(_ soundName: String) {
        stop()

        if soundName == "default" || soundName.isEmpty {
            AudioServicesPlaySystemSound(1007)
            return
        }

        guard let url = Bundle.main.url(
            forResource: (soundName as NSString).deletingPathExtension,
            withExtension: (soundName as NSString).pathExtension
        ) else {
            AudioServicesPlaySystemSound(1007)
            return
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.play()
            player = p
        } catch {
            AudioServicesPlaySystemSound(1007)
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }
}

@main
struct Drink_More_WaterApp: App {
    private let modelContainer: ModelContainer

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: ReminderEvent.self, AppSettings.self)
        } catch {
            let storeURL = ModelConfiguration().url
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension())
            do {
                container = try ModelContainer(for: ReminderEvent.self, AppSettings.self)
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        NotificationSoundPlayer.shared.stop()

        let store = HydrationEventStore(modelContainer: modelContainer)
        guard let settings = store.fetchOrCreateSettings() else { return }
        guard settings.hasCompletedSetup else { return }

        let responseToRecord: ResponseType? = switch response.actionIdentifier {
        case NotificationActions.drink:  .drink
        case NotificationActions.ignore: .ignore
        default: nil
        }
        guard let responseToRecord else { return }

        // Only backfill missed if there's existing history (not a fresh install)
        if await store.hasEvents() {
            await store.backfillMissed(settings: settings, lookback: .hours(24))
        }

        if let slot = SchedulingCalculator.slotTime(from: response.notification.request.identifier) {
            await store.record(.init(scheduledAt: slot, response: responseToRecord,
                                     personName: settings.personName))
        }
        NotificationScheduler(modelContainer: modelContainer).topUp(settings: settings)
    }
}

// MARK: - Background refresh

enum AppBackground {
    static func refresh(task: BGAppRefreshTask) {
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
                }
            } catch {
                Log.error("Background refresh failed: \(error)")
            }
        }
        task.expirationHandler = { work.cancel() }
    }
}
