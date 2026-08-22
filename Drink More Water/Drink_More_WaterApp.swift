import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import Combine
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
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }
}

// MARK: - Theme Manager
@MainActor
final class ThemeManager: ObservableObject {
    @Published var activeScheme: ColorScheme? = nil

    func update(from settings: AppSettings?) {
        switch settings?.colorSchemeOverride {
        case "light": activeScheme = .light
        case "dark":  activeScheme = .dark
        default:      activeScheme = nil
        }
    }

    /// Accepts a raw override string so callers from non-isolated
    /// (e.g. @Sendable) contexts can pass a Sendable value instead
    /// of the non-Sendable AppSettings model.
    func update(override: String?) {
        switch override {
        case "light": activeScheme = .light
        case "dark":  activeScheme = .dark
        default:      activeScheme = nil
        }
    }
}

private struct ThemeManagerKey: EnvironmentKey {
    static let defaultValue: ThemeManager = .init()
}
extension EnvironmentValues {
    var themeManager: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}

@main
struct Drink_More_WaterApp: App {
    private let modelContainer: ModelContainer
    private let themeManager = ThemeManager()
    private let colorSchemeObserver: NSObjectProtocol

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

        let context = ModelContext(container)
        if let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            themeManager.update(from: settings)
        }

        Task { @MainActor in
            await NotificationScheduler.requestAuthorization()
        }

        let mc = container
        let tm = themeManager
        colorSchemeObserver = NotificationCenter.default.addObserver(
            forName: .colorSchemeOverrideDidChange,
            object: nil,
            queue: .main
        ) { _ in
            // Extract only the Sendable String? — not the non-Sendable
            // AppSettings model — so we can cross into the @MainActor Task.
            let ctx = ModelContext(mc)
            let override: String? = (try? ctx.fetch(FetchDescriptor<AppSettings>()).first)?.colorSchemeOverride
            Task { @MainActor in
                tm.update(override: override)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(modelContainer: modelContainer)
                .preferredColorScheme(themeManager.activeScheme)
                .modelContainer(modelContainer)
                .environment(\.themeManager, themeManager)
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
        return [.banner, .list, .sound]
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

        await store.backfillMissed(settings: settings, lookback: .hours(24))
        if let responseToRecord,
           let slot = SchedulingCalculator.slotTime(from: response.notification.request.identifier) {
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
                    await store.backfillMissed(settings: settings, lookback: .hours(24))
                    NotificationScheduler(modelContainer: container).topUp(settings: settings)
                }
            } catch {
                Log.error("Background refresh failed: \(error)")
            }
        }
        task.expirationHandler = { work.cancel() }
    }
}
