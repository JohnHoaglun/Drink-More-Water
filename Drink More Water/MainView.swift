import SwiftUI
import SwiftData
import Combine
import UserNotifications

/// Spec: "Main screen — timer + drink/ignore buttons."
struct MainView: View {
    let modelContainer: ModelContainer

    @Environment(\.modelContext) private var context
    @Query private var events: [ReminderEvent]
    @Query(sort: \AppSettings.createdAt, order: .forward) private var settingsRows: [AppSettings]
    @State private var settingsLoaded = false
    @State private var now: Date = .now
    @Environment(\.colorScheme) private var colorScheme

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var calendar: Calendar { Calendar.current }

    private var settings: AppSettings? { settingsRows.first }
    private var isConfigured: Bool { settings?.hasCompletedSetup ?? false }

    /// A slot is only "answerable" if it fired within one full interval.
    /// Beyond that, it should have been backfilled as .missed.
    private var maxAnswerableOverdue: TimeInterval {
        TimeInterval(settings?.intervalMinutes ?? 60) * 60
    }

    // MARK: Slot logic

    /// The slot the user should answer right now.
    ///
    /// Priority:
    ///  1. The most recent slot that fired within the answerable window
    ///     (less than one interval ago) and has no recorded response.
    ///  2. Otherwise, the next upcoming slot (for the countdown).
    private var activeSlot: Date? {
        guard let settings else { return nil }
        let slots = SchedulingCalculator.slots(on: calendar.startOfDay(for: now), settings: settings)
        let recorded = Set(events.map { $0.scheduledAt })
        let open = slots.filter { !recorded.contains($0) }

        // Most recent overdue slot that's still within the answerable window.
        if let overdue = open.last(where: { $0 < now && now.timeIntervalSince($0) < maxAnswerableOverdue }) {
            return overdue
        }
        // Next upcoming slot.
        return open.first(where: { $0 >= now })
    }

    /// True while we are inside the daily reminder window.
    private var withinWindow: Bool {
        guard let settings else { return false }
        let slots = SchedulingCalculator.slots(on: calendar.startOfDay(for: now), settings: settings)
        guard let first = slots.first, let last = slots.last else { return false }
        return now >= first && now <= last
    }

    /// Show Drink/Ignore buttons when a slot has fired and is still
    /// unanswered (within the answerable window).
    private var isDue: Bool {
        guard let slot = activeSlot, withinWindow else { return false }
        return slot <= now
    }

    /// The next *upcoming* (future) slot, for the countdown display.
    private var nextUpcomingSlot: Date? {
        guard let settings else { return nil }
        let slots = SchedulingCalculator.slots(on: calendar.startOfDay(for: now), settings: settings)
        let recorded = Set(events.map { $0.scheduledAt })
        return slots.first { $0 >= now && !recorded.contains($0) }
    }

    /// First slot tomorrow, for the "all done" state.
    private var nextTomorrowSlot: Date? {
        guard let settings else { return nil }
        let tomorrow = calendar.startOfDay(for: now.addingTimeInterval(86400))
        return SchedulingCalculator.slots(on: tomorrow, settings: settings).first
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
        .onReceive(ticker) { now = $0 }
        .task {
            let store = HydrationEventStore(modelContainer: modelContainer)
            if let fetched = store.fetchOrCreateSettings() {
                if fetched.hasCompletedSetup {
                    await store.backfillMissed(settings: fetched, lookback: .hours(24))

                    // Only re-register notifications if they're actually
                    // missing. This prevents racing with the reschedule
                    // that didReceive already triggered, which was wiping
                    // out the re-registered (sound-bearing) requests.
                    let center = UNUserNotificationCenter.current()
                    let pending = await center.pendingNotificationRequests()
                    if pending.isEmpty {
                        NotificationScheduler(modelContainer: modelContainer).reschedule(settings: fetched)
                    }
                }
            }
            settingsLoaded = true
        }
    }

    // MARK: Active (timer) content

    private var activeContent: some View {
        VStack(spacing: 24) {
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
                Text("Next Glass")
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
        guard let settings, let slot = activeSlot else { return }
        let store = HydrationEventStore(modelContainer: modelContainer)
        let event = ReminderEvent(scheduledAt: slot, response: type, personName: settings.personName)
        Task { await store.record(event) }
    }

    // MARK: Formatting

    private func countdownLabel(to target: Date) -> String {
        let interval = max(0, target.timeIntervalSince(now))
        if interval < 60 {
            return "Now"
        }
        let minutes = Int(interval) / 60
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins) min"
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
