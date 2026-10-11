# TODO

## Open
- (none)

## Environment notes
- **Repo lives on a NAS-mounted SMB share** (`/Volumes/ai_projects/...`), not a local Unix volume. Consequences for git:
  - `core.filemode=false` and `core.trustmtime=false` are set in the local repo config to suppress mode-only diffs (SMB applies uniform 755 permissions) and phantom "modified" entries (unstable mtime over the network share).
  - A clean `git status` is the normal state on this volume. Do not interpret mode/mtime noise as uncommitted work; verify with `git diff HEAD` content checks before assuming changes exist.
  - ~404 build artifacts are tracked under `build/` (468 tracked files total). Consider untracking `build/` + adding a `.gitignore` entry if they cause friction after future local builds.
- **Xcode testing targets the connected physical iPhone** (John iPhone 16 Pro, iOS 26.6.2, network connection). `RunAllTests` runs the UI test plan on the device and shows the iOS XCUITest "automation running" banner on the phone. For quick verification, use `BuildProject` + `RunProject` instead of the full test plan.
