import SwiftUI
import SwiftData
import Combine
import UserNotifications

/// Spec: "Main screen — timer + drink/ignore buttons."
struct MainView: View {
    let modelContainer: ModelContainer

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var events: [ReminderEvent]
    @Query(sort: \AppSettings.createdAt, order: .forward) private var settingsRows: [AppSettings]
    @State private var settingsLoaded = false
    @State private var now: Date = .now
    @Environment(\.colorScheme) private var colorScheme

    // Tracks when the current slot became actionable, for timing/logging.
    @State private var isDueSince: Date? = nil

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var calendar: Calendar { Calendar.current }

    private var settings: AppSettings? { settingsRows.first }
    private var isConfigured: Bool { settings?.hasCompletedSetup ?? false }

    /// Buttons stay visible for 2 minutes after a slot fires.
    private let answerableWindow: TimeInterval = 120

    // MARK: Slot logic

    /// All slot times must match the scheduled notification time (+2 min shift) to keep the app state in sync with notifications.
    private func notificationAdjustedSlots(for date: Date, settings: AppSettings) -> [Date] {
        let rawSlots = SchedulingCalculator.slots(on: date, settings: settings)
        let shiftedSlots = rawSlots.map { slot in
            let shifted = slot.addingTimeInterval(120)
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: shifted)
            return calendar.date(from: comps)!
        }
        return shiftedSlots
    }

    private func datesAreClose(_ lhs: Date, _ rhs: Date, toleranceSeconds: TimeInterval = 2) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) <= toleranceSeconds
    }

    private func containsDate(_ set: Set<Date>, date: Date, toleranceSeconds: TimeInterval = 2) -> Bool {
        set.contains(where: { datesAreClose($0, date, toleranceSeconds: toleranceSeconds) })
    }

    private var activeSlot: Date? {
        guard let settings else { return nil }
        let startOfDay = calendar.startOfDay(for: now)
        let slots = notificationAdjustedSlots(for: startOfDay, settings: settings)

        let recorded = Set(events.map { event -> Date in
            let shifted = event.scheduledAt.addingTimeInterval(120)
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: shifted)
            return calendar.date(from: comps)!
        })

        let open = slots.filter { slot in
            !containsDate(recorded, date: slot)
        }

        if let overdue = open.last(where: { $0 < now && now.timeIntervalSince($0) < answerableWindow }) {
            return overdue
        }
        if let next = open.first(where: { $0 >= now }) {
            return next
        }
        return nil
    }

    private var withinWindow: Bool {
        guard let settings else { return false }
        let startOfDay = calendar.startOfDay(for: now)
        let slots = notificationAdjustedSlots(for: startOfDay, settings: settings)
        guard let first = slots.first, let last = slots.last else { return false }
        return now >= first && now <= last
    }

    private var isDue: Bool {
        guard let slot = activeSlot, withinWindow else { return false }
        return slot <= now
    }

    private var nextUpcomingSlot: Date? {
        guard let settings else { return nil }
        let startOfDay = calendar.startOfDay(for: now)
        let slots = notificationAdjustedSlots(for: startOfDay, settings: settings)
        let recorded = Set(events.map { event -> Date in
            let shifted = event.scheduledAt.addingTimeInterval(120)
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: shifted)
            return calendar.date(from: comps)!
        })
        return slots.first { slot in
            slot >= now && !containsDate(recorded, date: slot)
        }
    }

    private var nextTomorrowSlot: Date? {
        guard let settings else { return nil }
        let tomorrow = calendar.startOfDay(for: now.addingTimeInterval(86400))
        let slots = notificationAdjustedSlots(for: tomorrow, settings: settings)
        return slots.first
    }

    // MARK: Body

    var body: some View {
        ZStack {
            background

            if !settingsLoaded {
                ProgressView()
                    .tint(.white)
            } else if isConfigured {
                activeContent
            } else {
                placeholder
            }
        }
        .onReceive(ticker) { date in
            now = date
        }
        .onChange(of: isDue) { _, newValue in
            if newValue {
                isDueSince = Date()
                Log.info(
                    "Slot became actionable — showing Drink/Ignore buttons. slot=\(activeSlot?.formatted(date: .omitted, time: .standard) ?? "unknown")",
                    category: .ui
                )
            } else {
                if let since = isDueSince {
                    let duration = Date().timeIntervalSince(since)
                    Log.info(
                        "Slot no longer due — buttons hidden after \(String(format: "%.1f", duration))s",
                        category: .ui
                    )
                }
                isDueSince = nil
            }
        }
        .task {
            let store = HydrationEventStore(modelContainer: modelContainer)
            if let fetched = store.fetchOrCreateSettings() {
                if !events.isEmpty {
                    if fetched.hasCompletedSetup {
                        await store.backfillMissed(settings: fetched, lookback: .hours(24))
                        await store.autoIgnoreExpired(settings: fetched, window: answerableWindow)
                        NotificationScheduler(modelContainer: modelContainer).topUp(settings: fetched)
                    }
                } else {
                    NotificationScheduler(modelContainer: modelContainer).topUp(settings: fetched)
                    settingsLoaded = true
                    return
                }
            }
            settingsLoaded = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            NotificationSoundPlayer.shared.stop()
            Log.info("Scene phase changed to: \(newPhase)", category: .app)
            guard newPhase == .active, isConfigured, let settings, !events.isEmpty else { return }
            let store = HydrationEventStore(modelContainer: modelContainer)
            Task {
                await store.autoIgnoreExpired(settings: settings, window: answerableWindow)
                NotificationScheduler(modelContainer: modelContainer).topUp(settings: settings)
            }
        }
    }

    // MARK: Active (timer) content

    private var activeContent: some View {
        return VStack(spacing: 24) {
            statusDisplay

            Spacer()

            actionButtons

            Spacer()
        }
        .padding(24)
    }

    @ViewBuilder
    private var statusDisplay: some View {
        if isDue {
            Text("Time to Drink! 💧")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
        } else if let next = nextUpcomingSlot {
            VStack(spacing: 6) {
                Text("Next Drink")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text(countdownLabel(to: next))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: 280)
        } else {
            VStack(spacing: 6) {
                Text("All Done Today 🎉")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                if let next = nextTomorrowSlot {
                    Text("Next at \(next.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(maxWidth: 280)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isDue {
            VStack(spacing: 14) {
                Button {
                    respond(.ignore)
                } label: {
                    Label("Ignore", systemImage: "xmark.circle.fill")
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button {
                    respond(.drink)
                } label: {
                    Label("Drink", systemImage: "drop.fill")
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .frame(maxWidth: 300)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .animation(.easeInOut(duration: 0.25), value: isDue)
        }
    }

    // MARK: Placeholder

    private var placeholder: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.7))
            Text("Set up your schedule to get started")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tap the Setup tab to choose your start time, end time, and interval.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: 280)
        .padding(24)
    }

    // MARK: Actions

    private func respond(_ type: ResponseType) {
        NotificationSoundPlayer.shared.stop()

        guard let settings, let slot = activeSlot else {
            Log.warn("respond() called but no active slot or settings available", category: .interaction)
            return
        }

        let latencyStr: String
        if let since = isDueSince {
            latencyStr = String(format: "%.1f", Date().timeIntervalSince(since)) + "s"
        } else {
            latencyStr = "unknown"
        }

        Log.info(
            "User responded: \(type) — slot=\(slot.formatted(date: .omitted, time: .standard)), timeVisible=\(latencyStr)",
            category: .interaction
        )

        let store = HydrationEventStore(modelContainer: modelContainer)
        let event = ReminderEvent(scheduledAt: slot, response: type, personName: settings.personName)
        Task {
            await store.record(event)
            DispatchQueue.main.async {
                settingsLoaded = false
                settingsLoaded = true
            }
        }
    }

    // MARK: Formatting

    private func countdownLabel(to target: Date) -> String {
        let interval = max(0, target.timeIntervalSince(now))
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // MARK: Background

    private var background: some View {
        Image("Water_bottle")
            .resizable()
            .scaledToFill()
            .overlay(
                Color.black.opacity(colorScheme == .dark ? 0.55 : 0.25)
            )
            .ignoresSafeArea()
    }
}
