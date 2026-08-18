# Drink More Water

An iPhone app that reminds you to drink water on a configurable schedule, tracks whether you drank, ignored, or missed each reminder, and summarizes your habits over time — all stored locally on-device.

> This README is drafted to travel with the project into its GitHub repo (e.g. as the repo root `README.md`). Full requirements and rationale live in the companion spec note, `Hydration-App-for-Iphone-Specs.md`.

## Status

Early spec / pre-development. Not yet started in Xcode.

## Features (v1)

- Configurable reminder window (start time / end time) and interval
- Silent or audible reminders, with a system-sound tone picker
- Drink / Ignore response — actionable directly from the notification or from the app's main screen
- Automatic "missed / no response" tracking when a reminder goes unanswered
- Day / week / month stats, viewable as a chart or a numeric list (toggleable)
- Local-only storage — no account, no backend
- Clear history, and export history as CSV (shareable via email or any share-sheet target)
- Light and dark mode

## Planned for v2

- Apple Watch companion app (custom drink/ignore actions, dedicated watchOS UI)
- Custom bundled water-themed alert sounds, beyond the iOS system sound picker

## Requirements

- Xcode (version TBD at build time)
- iOS deployment target: current major iOS release through N-2, re-evaluated at build time
- Swift Charts and SwiftData are used by default (require iOS 17+); if the supported iOS range dips below that, the data layer falls back to Core Data and charts fall back to a custom view

## Architecture

- SwiftUI + SwiftData, MVVM, fully on-device (no backend)
- `NotificationScheduler` pre-schedules local notifications for the reminder window using `UNUserNotificationCenter`, with Drink/Ignore `UNNotificationAction`s
- `ReminderEvent` (SwiftData model) records each response (`drink` / `ignore` / `missed`); missed events are backfilled by detecting unanswered past slots rather than relying on a persistent background process (iOS does not support that)
- `StatsAggregator` computes day/week/month rollups on demand from stored events
- `CSVExporter` builds CSV export data, shared via `ShareLink`

See the full architecture sketch, data model, and resolved design decisions in the spec note: `Hydration App for Iphone.md`.

## Project Structure (planned)

```
HydrationApp/
├── HydrationApp.swift
├── Models/
│   ├── ReminderEvent.swift
│   └── Settings.swift
├── Services/
│   ├── NotificationScheduler.swift
│   ├── NotificationDelegate.swift
│   ├── StatsAggregator.swift
│   └── CSVExporter.swift
├── Views/
│   ├── MainView.swift
│   ├── SetupView.swift
│   ├── ReportingView.swift
│   │   ├── StatsChartView.swift
│   │   └── StatsListView.swift
│   └── AboutView.swift
└── ViewModels/
    ├── MainViewModel.swift
    ├── SetupViewModel.swift
    └── ReportingViewModel.swift
```

## License

TBD.

