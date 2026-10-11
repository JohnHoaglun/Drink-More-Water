# Changelog

## 1.0.3 — build-17 (2026-10-11)

- Docs: added `TODO.md` with environment notes — the repo now lives on a NAS-mounted SMB share (local git config sets `core.filemode=false` / `core.trustmtime=false` to suppress mode/mtime noise), and Xcode test runs target the connected physical iPhone (`RunAllTests` shows the XCUITest automation banner on-device; prefer `BuildProject` + `RunProject` for quick verification).

## 1.0.2 — build-16 (2026-10-11)

- Fixed: tapping OK on the "Schedule updated" alert in Setup left the user on the Setup tab, feeling locked in. OK now returns to the Home tab.
  - `RootView` now owns the `TabView` selection (`AppTab`); `SetupView` takes an `onDone` callback that the alert invokes.

## 1.0.1 — build-15 (2026-10-11)

- Added a "Reminder timer" toggle to the Setup page (Timer section between Schedule and Alerts).
  - When off: all pending notifications are cleared, the top-up stops adding new ones, and the Home screen shows a "Timer Stopped" state instead of the countdown.
  - When back on: the full 24-hour schedule is re-anchored to the current time and reminders resume.
- `AppSettings` gains `isTimerEnabled` (default `true`), persisted with the rest of the settings backup/restore.
- `AppSettingsBackup.restore` defaults `isTimerEnabled` to `true` when the key is absent, so restoring a pre-feature backup keeps reminders running.
- Startup log now includes the timer state (`timer=on/off`).
- Unit tests: `AppSettingsTimerTests` (default state, backup round-trip, restore default when key missing).
