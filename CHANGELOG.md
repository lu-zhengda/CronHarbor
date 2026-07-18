# Changelog

All notable changes to CronHarbor are documented here. The project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and intends to use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Scheduled-start tracking: CronHarbor now observes the cron daemon's `(user) CMD (…)` entries in the unified log — read-only, current user only. Job detail shows the last observed start, and Run History gains a Scheduled tab listing observed starts. Because macOS keeps these Info-level entries only briefly, CronHarbor polls every two minutes while jobs are installed and accumulates what it sees for the session; the UI states plainly that starts prove launch, not completion or exit status.
- Optional menu bar countdown ("12m", "3h", "Tue") to the next installed run, off by default.
- Optional local notification when a Run Now finishes, including exit status; off by default, requests authorization on first enable, and never applies to cron's own scheduled runs.

### Tests

- Added daemon log parsing coverage: user filtering, non-CMD exclusion, parentheses in commands, and exact-user matching.

## [0.3.0] - 2026-07-18

### Added

- Backups browser in Settings: list every private crontab backup with its date and size, reveal the folder in Finder, restore a backup through the same digest-checked install path as a normal apply (the current crontab is backed up first), and prune old backups while keeping the newest 20.
- Launch-at-login toggle in Settings using `SMAppService`, with graceful reporting when macOS declines the change.
- Live "next occurrences" preview in the job editor: the next three run times update as the schedule expression is typed.
- Upcoming-runs card in job detail now lists the next three occurrences instead of one.
- Duplicate action in job detail that opens a prefilled new-job draft.
- Run history gained a failures-only filter and a confirmed Clear History action.

### Changed

- Schedule descriptions now cover many more expressions — minute/hour steps, hour stop lists, weekday and weekend sets, day-of-month lists, month sets, and multiple daily times — with locale-aware time formatting. Expressions that cannot be described confidently (including schedules where cron ORs restricted day-of-month and day-of-week fields) still fall back to the raw source rather than risking a wrong paraphrase.
- Schedule validation errors now name the failing cron field and the reason, such as an out-of-range value or a malformed step, instead of one generic message.

### Tests

- Added formatter coverage for interval, clock-time, weekday, day-of-month, month, macro, and fallback descriptions.
- Added model coverage for duplicate drafts, clearing run history, and backup restore (including the staged-changes guard).

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
