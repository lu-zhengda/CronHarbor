# CronHarbor safety model

CronHarbor changes executable configuration. Its interface is designed to make that power visible, reviewable, and recoverable, but it cannot make an unsafe command safe.

## Trust boundary

CronHarbor acts with the permissions of the signed-in macOS user.

- It invokes the fixed executable `/usr/bin/crontab` directly.
- Reads use only `crontab -l`; installs pass one private temporary file path.
- There is no `sudo`, other-user selector, privileged helper, or direct cron spool edit.
- It does not install a daemon or replace the system cron scheduler.
- A job command and any program it launches have the same user-level access they would have under cron.

CronHarbor has no network or telemetry client. A command launched by cron or **Run Now** may still use the network because it is user-supplied executable content.

## Source preservation

The complete crontab is parsed into byte-backed lines. CronHarbor recognizes blank lines, comments, environment assignments, supported jobs, and its own transparent metadata. Anything else is opaque.

Opaque source is not guessed at or normalized. It stays in the candidate document exactly as read and is surfaced as a protected-line diagnostic and a visible attention row. For untouched recognized source, CronHarbor also preserves content bytes, LF versus CRLF, tabs and spacing, and whether the final line has a terminator.

Authoritative `crontab -l` output has a 16 MiB safety ceiling. If that ceiling is exceeded, CronHarbor refuses the read before parsing or writing. It never treats a retained prefix as the complete crontab.

Creating or editing a job adds a visible metadata comment:

```text
# CronHarbor:job:<id>:<base64-encoded-name>
```

Pausing a job replaces only its target block with a CronHarbor disabled marker that embeds the original job bytes. Enabling it can therefore restore those bytes exactly. Editing an imported job intentionally converts that target into a CronHarbor-managed block. Deleting a job is also explicit and removes only its marker, when present, and target line.

No preservation promise applies to the exact text of a job the user has explicitly edited: CronHarbor must render the new values. Neighboring and protected lines remain authoritative. If the same CronHarbor identity appears more than once, every ambiguous entry is protected from editing and manual execution; unrelated jobs remain editable.

## Apply transaction

The UI stages create, update, pause, and delete operations in memory. Until **Review & Apply** is confirmed, the installed crontab is unchanged.

An apply transaction is serialized and follows this order:

1. Re-read the installed user crontab.
2. Compare its SHA-256 digest with the snapshot on which the staged changes were based.
3. Stop without backing up or installing if another tool changed it.
4. Save the exact current bytes to a new private backup.
5. Re-read the crontab after backup creation and stop if it changed during that suspension point.
6. Write the candidate to an exclusively created private `0600` temporary file.
7. Ask `/usr/bin/crontab` to install that file.
8. Re-read the installed crontab and require an exact byte-for-byte match.

The backup directory is forced and verified at mode `0700`; backup files are exclusively created and verified at mode `0600`. CronHarbor reports the backup path if readback does not match or cannot be performed after a successful install command. It does not currently perform an automatic rollback or automatically prune old backups.

`crontab` does not expose a cross-process compare-and-swap primitive. The second digest check narrows the external-write window to the final read/install boundary, but another tool that writes in that last interval cannot be locked out by CronHarbor. Exact readback confirms the post-install bytes; it cannot recover an external write that was overwritten inside that final race.

Backups live at:

```text
~/Library/Application Support/CronHarbor/Backups/
```

If a write reports a readback mismatch, inspect the installed state with `crontab -l` before making another change. To restore, review the desired backup first and then use the standard `crontab <path>` command yourself.

## Run Now semantics

**Run Now** is a confirmed convenience execution path, not a simulation of the scheduler clock.

- CronHarbor re-reads the installed crontab and resolves the selected job in that current source.
- The schedule, enabled/paused state, and `@AppleNotOnBattery` restriction are ignored for this manual execution.
- Staged source is not installed source; CronHarbor disables manual execution for that job until its changes are applied or discarded.
- Immediately before launch, the SHA-256 revision of the complete installed crontab and the selected job's name, schedule, command, enabled state, ownership, and AC restriction must still match the confirmed presentation. This also binds effective preceding environment assignments. A mismatch runs nothing and requires refresh.
- The command is executed as `<shell> -c <command>` using the `SHELL` effective above the job, or `/bin/sh` by default.
- The working directory is `HOME`; absent configuration falls back to the current user's home directory.
- CronHarbor preserves effective crontab environment assignments and supplies `HOME`, `LOGNAME`, `USER`, `SHELL`, and a minimal `/usr/bin:/bin` `PATH` when needed.
- It does not inherit arbitrary variables from the GUI app. This reduces accidental leakage of loader variables, app secrets, and XPC state.
- Cron's first unescaped `%` splits the shell command from standard input; later unescaped percent signs become newlines. Escaped percent signs remain literal.
- A byte-identical invocation cannot be started twice concurrently through the executor.

This is deliberately close to cron, but it cannot reproduce every daemon-level circumstance. Shell profiles are not sourced automatically, the Mac's live filesystem and credentials still matter, and the command can have irreversible effects. Review the installed command and effective restrictions before running it.

## History and sensitive output

CronHarbor records only manual executions it starts. It does not observe, infer, or claim history for executions performed by the cron daemon.

For each manual run it stores the start time, duration, exit status, standard output, and standard error. It retains no more than 1 MiB per output stream, continues draining excess bytes, and inserts a visible truncation marker. The newest 100 records are stored in:

```text
~/Library/Application Support/CronHarbor/run-history.json
```

The containing directory is repaired to mode `0700`, and history replacements are staged privately at `0600` before an atomic same-directory replacement. The file is not separately encrypted or redacted. Avoid printing secrets from jobs you run manually. Removing the file clears the persisted history; quit CronHarbor first so a concurrent completed run does not recreate it unexpectedly.

CronHarbor does not currently provide a Stop button for a manual run. A long-running child continues until it exits or is terminated through another system tool.

## Scheduling limits

- Upcoming times are calculated locally for display; `/usr/bin/crontab` and the system daemon are authoritative.
- `@reboot` does not have a deterministic next wall-clock time.
- The cron daemon does not catch up an event missed while the Mac is asleep.
- CronHarbor is not a `launchd` editor and does not add wake, retry, timeout, or dependency semantics.
- Unsupported syntax is protected instead of interpreted.

## Release trust

`script/package_release.sh` always verifies bundle structure, architecture, and the code signature from a clean archive extraction. Without `CODESIGN_IDENTITY`, it creates an ad-hoc-signed archive suitable for local validation. Setting that variable signs with the supplied identity and hardened runtime; notarization and stapling additionally require a notarytool keychain profile in `NOTARYTOOL_PROFILE`.

Code-signature validity, Developer ID identity, notarization, and source provenance are separate properties. Do not bypass Gatekeeper merely because an archive has the CronHarbor name. The Homebrew formula builds the app locally from tagged source; it does not turn an ad-hoc release archive into a trusted binary.

## Recovery checklist

If you suspect an incorrect edit:

1. Do not apply additional staged changes.
2. Inspect the live source with `crontab -l`.
3. Locate the newest relevant backup by timestamp and inspect its contents.
4. Restore only after confirming that the backup is the version you want.
5. Report any loss of untouched bytes, missed conflict, or readback mismatch as a security-sensitive defect.
