# Project Memories

This file captures workflow notes that future coding agents should preserve.

## Device Build Policy

Every code turn that will be built and loaded onto the phone must have a unique build number before device testing.

Required steps before loading code on the phone:

1. Increment `Constants.buildTag` in `Drink More Water/Constants.swift`.
2. Commit the change with a build-numbered commit message, following the existing pattern:
   `build-N: short description`
3. Push the commit to the upstream branch before installing/running that build on the phone.

The About page must display `Constants.buildTag` so the build loaded on a phone can be identified from the UI as well as from logs.

Current observed branch policy:

- Active branch: `dev`
- Upstream: `origin/dev`
- Recent commits use messages such as `build-5: fix fresh-install buttons bug, add debug logging toggle, add startup state logging`

## Device Debug Log

The app writes a debug log through iCloud that can be tailed from the Mac:

```sh
tail -n 20 -F ~/Library/Mobile\ Documents/iCloud~Hoaglun~com~Drink-More-Water/Documents/app_debug.log
```

Use this for phone-side debugging after notification events fire.

## Notification Sound Finding

On August 31, 2026, device testing confirmed that custom notification audio works on the locked iPhone when Apple Watch notification mirroring is disabled for this app.

Observed behavior:

1. With Apple Watch mirroring enabled, a locked/asleep iPhone may route the alert to Apple Watch. In that path, the watch played only the default system beep.
2. After disabling mirrored notifications for Drink More Water in the Watch app, locked-phone reminders played the selected custom CAF sound on the iPhone.
3. Logs confirmed pending notifications had `userSound=Drink4.caf`, `audible=true`, and a non-nil `UNNotificationSound`.

Conclusion: the CAF files and iPhone notification payload are valid. If custom audio is not heard while Apple Watch is paired, first check Watch notification mirroring before reinvestigating app-side sound compliance.
