
#ai #iphone #ios #llm #applestore

# Hydration App for iPhone

## Overview
An iPhone app that reminds the user to drink water at a configurable interval during a configurable daily window, tracks acknowledgements, and summarizes drinking habits over time.

Title: "Drink more water"

## Target Platform
- iOS deployment target: current major iOS release down through N-2 (i.e. support the current version and the two prior major versions) — re-evaluate this range periodically as new iOS versions ship
- Companion Apple Watch app: **Deferred to v2.** v1 ships iPhone-only; standard local notifications will mirror to Watch by default, but custom drink/ignore actions and a dedicated watchOS UI are out of scope for v1.

## Functional Requirements

### Reminders
- Alert the user every (B) minutes to drink water, between a configurable (morning) start time and (evening) end time
- (morning) start time is user-configurable
- (evening) end time is user-configurable
- (B) minutes between drinks is user-configurable
- Silent alert option
- Audible alert option
- Selectable audible tone, chosen from the iOS system sound picker (built-in sounds only for v1)
- No alerts outside the (morning)–(evening) window

### Acknowledgement
- Green "drink" button to acknowledge taking a drink of water
- Red "ignore" button to acknowledge not taking a drink of water
- Both actions are available directly on the notification (inline notification action buttons), as well as on the main screen — the user should not need to open the app to respond

### Stats & Tracking
- Summarize the number of "drink," "ignore," and "missed / no response" events per day, per week, per month
- A reminder becomes "missed / no response" if the user hasn't tapped drink or ignore by the time the next reminder fires
- Day/week/month boundaries are based on the device's current local time at the moment of each event (no fixed "home" timezone)
- Track the (single) person's name as a display label associated with the drink stats — no multi-profile support
- Store counts locally on-device
- Ability to clear all history
- Ability to export history as CSV and share it via email (e.g. to oneself), using the native iOS share sheet

## Screens
- Setup screen
- Reporting screen — includes a view toggle (e.g. segmented control) to switch between a chart view and a numeric/list view of drink/ignore/missed stats; only one view shown at a time
- About screen
- Main screen — timer + drink/ignore buttons

## Look & Feel
- Light and dark mode support
- Background image of a water bottle
- Water bottle icon for the iOS launcher

## Technical Constraints & Notes
- **Background execution**: iOS does not support a persistently-running background process to track time until the next notification. Use `UNUserNotificationCenter` to schedule local notifications in advance (e.g. schedule the day's reminders up front, or use repeating interval requests); reschedule when settings change. `BGAppRefreshTask` can be used as a daily top-up/fallback, not as the primary mechanism.
- **Local storage**: plain counts likely won't scale well in UserDefaults once daily/weekly/monthly aggregation and history are needed — consider SwiftData or Core Data.
- **Notification permissions**: need an onboarding/first-run flow requesting notification permission, plus handling for the case where the user denies it.

## Open Questions
1. ~~What are the min/max supported iOS versions (X)/(Y)?~~ **Resolved: support current iOS and N-2.**
2. ~~Is Apple Watch support in scope for v1?~~ **Resolved: deferred to v2.**
3. ~~"Selectable audible town" — confirm meant audible tone.~~ **Resolved: yes, "tone" (typo fixed in spec). v1 uses iOS system sound picker; custom bundled water sounds (e.g. splash) deferred to v2.**
4. ~~Is "person's name" tracking multi-user or single-user?~~ **Resolved: single user. The name is just a display label (e.g. for the reporting screen), not a profile-switching system — no multi-profile UI needed.**
5. ~~Should notifications include inline action buttons?~~ **Resolved: yes — drink/ignore should be actionable directly from the notification (via `UNNotificationAction`), so the user doesn't need to open the app. The same buttons remain available on the main screen too.**
6. ~~Is a non-response counted as "ignore" or a separate state?~~ **Resolved: separate third state — "missed / no response," distinct from an explicit "ignore" tap.**
7. ~~How should day/week/month boundaries be handled across timezone changes/travel?~~ **Resolved: always bucket by the device's current local time at the moment of each event — no fixed "home" timezone.**
8. ~~Should the reporting screen show charts/graphs, or just numeric summaries?~~ **Resolved: both, user-toggleable — a view switcher (e.g. segmented control/button) lets the user swap between a chart view and a numeric/list view, one at a time.**
9. ~~Should there be a way to clear history or export data?~~ **Resolved: yes, both, in v1.**
   - **Clear history**: a "clear all history" action (setup or about screen).
   - **Export**: generate a CSV of the drink/ignore/missed history and let the user email it (e.g. to themselves), via iOS's native share sheet / `MFMailComposeViewController` — no custom email infrastructure needed, since the share sheet already supports Mail as a destination.

## Future / v2 Scope
- Apple Watch companion app — custom drink/ignore complications/actions, dedicated watchOS UI, WatchConnectivity sync
- Custom bundled water-themed alert sounds (e.g. splash tone), beyond the iOS system sound picker

## Technical Architecture (Draft)

Stack: SwiftUI + SwiftData, MVVM. No backend — fully local/on-device.

### App structure
```
HydrationApp/
├── HydrationApp.swift          // @main, SwiftData ModelContainer setup
├── Models/
│   ├── ReminderEvent.swift     // SwiftData @Model
│   └── Settings.swift          // SwiftData @Model (singleton) or AppStorage-backed struct
├── Services/
│   ├── NotificationScheduler.swift   // schedules/reschedules UNNotificationRequests
│   ├── NotificationDelegate.swift    // UNUserNotificationCenterDelegate, handles actions + no-response detection
│   ├── StatsAggregator.swift         // day/week/month rollups from ReminderEvent history
│   └── CSVExporter.swift             // builds CSV, hands to ShareLink/MFMailComposeViewController
├── Views/
│   ├── MainView.swift           // timer + drink/ignore buttons
│   ├── SetupView.swift          // start/end time, interval, sound, name, silent/audible
│   ├── ReportingView.swift      // container: view-toggle between ChartView/ListView
│   │   ├── StatsChartView.swift // Swift Charts
│   │   └── StatsListView.swift  // numeric table
│   └── AboutView.swift
└── ViewModels/
    ├── MainViewModel.swift
    ├── SetupViewModel.swift
    └── ReportingViewModel.swift
```

### Data model (SwiftData)

```swift
@Model
class ReminderEvent {
    var timestamp: Date
    var response: ResponseType   // .drink, .ignore, .missed
    var personName: String       // denormalized display label
}

enum ResponseType: String, Codable {
    case drink, ignore, missed
}

@Model
class AppSettings {
    var startTime: DateComponents   // "morning" — hour/minute only
    var endTime: DateComponents     // "evening" — hour/minute only
    var intervalMinutes: Int        // (B)
    var isAudible: Bool
    var soundName: String           // system sound identifier
    var personName: String
    var colorSchemeOverride: String? // nil = follow system, else "light"/"dark"
}
```
Single `AppSettings` row acts as the settings singleton. `ReminderEvent` rows accumulate; `StatsAggregator` groups them by `Calendar.current` day/week/month using the device's current local time (per the resolved timezone decision) — no stored timezone field needed since grouping always happens live against current locale/calendar.

### Notification scheduling
- `NotificationScheduler` computes all fire times between `startTime` and `endTime` at `intervalMinutes` spacing for a rolling window (e.g. today + tomorrow), and submits one `UNNotificationRequest` per slot with a unique identifier (e.g. `reminder-yyyyMMdd-HHmm`).
- Each request includes two `UNNotificationAction`s ("Drink", "Ignore") grouped under a `UNNotificationCategory` (e.g. `"HYDRATION_REMINDER"`).
- Re-run scheduling: on app launch, on settings change (Setup screen save), and opportunistically via `BGAppRefreshTask` once daily to keep the rolling window topped up — this is the fallback, not the primary delivery mechanism (per the earlier background-execution note).
- `NotificationDelegate.userNotificationCenter(_:didReceive:)` handles the Drink/Ignore action taps and writes a `ReminderEvent`.
- **No-response detection**: when a new `ReminderEvent` is about to be written (or when a new reminder fires / app becomes active), check for any earlier scheduled slot with no matching event and backfill it as `.missed`. This avoids needing a separate background timer just to detect silence.

### Reporting
- `StatsAggregator` exposes `[DateInterval: (drink: Int, ignore: Int, missed: Int)]` for day/week/month granularities, computed on-demand from `ReminderEvent` queries (SwiftData `#Predicate` + `Calendar` date ranges) — no separate pre-aggregated table needed at this scale.
- `StatsChartView` uses **Swift Charts** (`BarMark`, one series per response type).
- `StatsListView` renders the same aggregated data as a simple table/list.
- A segmented control at the top of `ReportingView` toggles between the two, backed by `@State private var reportMode: .chart | .list`.

### Export / clear
- `CSVExporter` builds a CSV string from `ReminderEvent` rows (timestamp, response, personName) and exposes it via `ShareLink` (simplest, lets the user pick Mail or any other share target) — `MFMailComposeViewController` is a fallback only if you want a "always opens Mail directly" guarantee.
- "Clear history" deletes all `ReminderEvent` rows via a SwiftData batch delete, with a confirmation alert.

### Open build-time decision
- Exact minimum iOS version (drives whether Swift Charts / SwiftData are available without fallback — both require iOS 17+; if N-2 at build time dips below that, fall back to Core Data + a simple bar-drawing view).
