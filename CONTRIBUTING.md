# Contributing to CronHarbor

Thank you for helping make cron safer and easier to understand on macOS.

## Development setup

You need macOS 14 or later and a Swift 6 toolchain. Xcode 16 or later is recommended.

From a checkout:

```sh
swift build
swift test
```

To stage and launch a development app bundle:

```sh
./script/build_and_run.sh
```

The app runs as a menu bar accessory and writes a development bundle to `dist/CronHarbor.app`.

## Safety invariants

Changes are welcome only if these properties remain explicit and tested:

1. CronHarbor manages the current user only through the fixed `/usr/bin/crontab` executable. Do not add `sudo`, `crontab -u`, direct spool edits, or shell construction around crontab operations.
2. Untouched input is byte-authoritative. Preserve non-UTF-8 data, line endings, whitespace, comments, environment lines, opaque syntax, and a missing final newline.
3. Ambiguous syntax is opaque. Do not guess at an entry simply to make it editable.
4. Every install must detect stale source, back up the exact current bytes before writing, install through a private file, and verify exact readback.
5. Tests must never read or install the developer's real crontab. Use protocol fakes and temporary directories.
6. **Run Now** must not inherit the app's full environment. The confirmation must accurately describe the installed command that will execute and every ignored restriction, and launch must fail if the complete installed source revision or selected execution fields changed.
7. Ad-hoc signing must never be described as Developer ID trust or notarization.

Read [docs/SAFETY.md](docs/SAFETY.md) before changing parsing, editing, execution, or release code.

## Making a change

- Keep `CronHarborCore` independent of SwiftUI when the behavior is reusable or safety-critical.
- Add focused tests for the success path and the relevant failure boundary.
- Prefer dependency-injected process and filesystem collaborators over global state.
- Keep user-facing language concrete: say what will be read, written, ignored, or executed.
- Preserve staged-edit semantics; an editor dismissal must not silently install source.
- Update `CHANGELOG.md` for user-visible behavior.

Run the complete suite before submitting:

```sh
swift test
```

For release or bundle changes, also run:

```sh
./script/package_release.sh
```

The packaging script builds both Apple silicon and Intel slices and validates the bundle signature. Its default signature is ad hoc unless release credentials are supplied.

## Tests worth adding

Parser and editor changes should cover raw-byte round trips, CRLF and no-final-newline input, duplicate jobs, malformed UTF-8, unsupported syntax, CronHarbor marker validation, and edits beside protected lines.

Repository changes should cover stale-digest conflicts, backup-before-install ordering, permissions, install failure, readback mismatch, and concurrent writes.

Execution changes should cover effective crontab environment ordering, account-derived defaults, absolute shell and home validation, `%` handling, bounded output capture, exact installed-job resolution, and duplicate suppression without launching a real user command.

## Pull requests

Keep pull requests focused. Describe:

- the user-visible outcome;
- safety properties affected;
- tests added or run;
- any migration or source-rendering impact;
- screenshots for meaningful UI changes.

Do not include real crontabs, personal paths, command output containing secrets, signing identities, or notarization credentials.

## Reporting security issues

Please do not open a public issue for a vulnerability. Follow [SECURITY.md](SECURITY.md).
