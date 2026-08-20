import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import Combine

// MARK: - Theme Manager
// Using a dedicated class allows the ColorScheme to update reactively.
// @State cannot be used in a @main App struct.
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
}

// Environment key extension
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

        // Configure notification delegate
        NotificationDelegate.shared.modelContainer = container
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // Register background refresh task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Constants.bgTaskID,
            using: nil
        ) { task in
            guard let bgTask = task as? BGAppRefreshTask else { return }
            AppBackground.refresh(task: bgTask)
        }

        // Fetch initial settings and update theme
        let context = ModelContext(container)
        if let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            themeManager.update(from: settings)
        }

        // Request notification authorization
        Task { @MainActor in
            await NotificationScheduler.requestAuthorization()
        }

        // Observe color scheme changes from SetupView
        let mc = container
        let tm = themeManager
        colorSchemeObserver = NotificationCenter.default.addObserver(
            forName: .colorSchemeOverrideDidChange,
            object: nil,
            queue: .main
        ) { _ in
            let ctx = ModelContext(mc)
            if let s = try? ctx.fetch(FetchDescriptor<AppSettings>()).first {
                Task { @MainActor in
                    tm.update(from: s)
                }
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
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
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
        NotificationScheduler(modelContainer: modelContainer).reschedule(settings: settings)
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
                    NotificationScheduler(modelContainer: container).reschedule(settings: settings)
                }
            } catch {
                Log.error("Background refresh failed: \(error)")
            }
        }
        task.expirationHandler = { work.cancel() }
    }
}
