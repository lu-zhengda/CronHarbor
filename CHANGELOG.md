# Changelog

All notable changes to CronHarbor are documented here. The project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and intends to use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-07-15

### Changed

- Rebuilt CronHarbor as a true menu-bar-first app with no dashboard window at launch.
- Moved job search, status filters, upcoming-run summary, job details, editing, staged-change review, and Run Now history into one compact panel.
- Replaced modal editing with an inline, model-backed editor that preserves in-progress typing when the menu closes.
- Added persistent staged-only warnings and a dedicated review screen with exact commands and installed delete-target details.
- Kept the prominent upcoming-run summary anchored to the installed crontab while edits are staged.
- Kept Settings as the only deliberate secondary window.

### Removed

- Removed the three-column dashboard and its launcher-style menu popover.

### Tests

- Added editor lifecycle, installed delete-target snapshot, and discard-failure coverage.
- Added a release guard that rejects normal SwiftUI window scenes and verifies `LSUIElement` remains enabled.

## [0.1.0] - 2026-07-14

### Added

- Native macOS 14+ SwiftUI menu bar app with a three-pane cron dashboard.
- Search and status filters, schedule presets, local next-run previews, and `@AppleNotOnBattery` editing.
- Staged create, edit, pause, resume, and delete operations with an explicit review-and-apply confirmation.
- Lossless crontab parsing that preserves untouched raw bytes, line endings, comments, environment assignments, and opaque source.
- Transparent job metadata and reversible paused-job markers.
- Current-user-only `/usr/bin/crontab` integration with secure temporary files.
- Serialized, digest-checked installs with two pre-install source checks, private backups, and exact post-install readback.
- Confirmed **Run Now** execution with effective cron environment assignments, sanitized defaults, cron `%` preprocessing, output capture, and concurrent duplicate suppression.
- Whole-crontab revision and exact installed-job matching before **Run Now**, staged-job blocking, and explicit paused/AC restriction warnings.
- Correct macOS `@AppleNotOnBattery` command-prefix placement, DST-fold handling, and day-field wildcard semantics.
- Protected attention rows for opaque source and duplicate managed identities.
- Bounded 1 MiB-per-stream **Run Now** capture with visible truncation markers.
- Fail-closed authoritative crontab reads with a separate 16 MiB safety ceiling.
- Private local history for the newest 100 CronHarbor-started runs.
- Minute-by-minute refresh of upcoming-run estimates in the dashboard and menu bar.
- Universal arm64 and x86_64 packaging with optional Developer ID signing and notarization.
- Source-build distribution through the `lu-zhengda/tap` Homebrew tap.
- Deterministic app icon and product design reference artwork.

### Security

- Backups, install temporary files, and run history are restricted to the current user with POSIX permissions.
- Unsupported or ambiguous crontab syntax is protected rather than rewritten.
- Default packaging is documented as ad-hoc signed, not notarized.
