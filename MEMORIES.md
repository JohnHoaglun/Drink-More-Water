# Project Memories

This file captures workflow notes that future coding agents should preserve.

## Device Build Policy

Every code turn that will be built and loaded onto the phone must have a unique build number before device testing.

Required steps before loading code on the phone:

1. Increment `Constants.buildTag` in `Drink More Water/Constants.swift`.
2. Commit the change with a build-numbered commit message, following the existing pattern:
   `build-N: short description`
3. Push the commit to the upstream branch before installing/running that build on the phone.

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
