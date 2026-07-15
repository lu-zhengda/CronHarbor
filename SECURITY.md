# Security policy

CronHarbor manages executable configuration, so reports involving unintended command execution, crontab corruption, source loss, permission mistakes, or bypassed conflict checks are treated as security-sensitive.

## Supported versions

Security fixes are made on `main` and, after releases exist, the latest published minor release. Older snapshots are not guaranteed to receive backports.

## Reporting a vulnerability

Please use GitHub's **Report a vulnerability** flow to open a private security advisory for this repository. Include:

- affected commit or version;
- macOS and Swift/Xcode versions;
- minimal crontab input with secrets removed;
- expected and observed behavior;
- whether a real crontab was written or a command executed;
- reproduction steps or a focused test, if safe.

Do not paste live crontabs, command output, usernames, home paths, access tokens, or signing credentials into a public issue. If private advisories are unavailable, contact the maintainer through the GitHub profile and share only enough public information to establish a private channel.

You should receive an acknowledgement within seven days. Please allow time for validation and a coordinated fix before public disclosure.

## High-priority report areas

- Modification of bytes outside an explicitly targeted job block
- An install after the source digest changed
- Missing or overly broad permissions on backups, temporary files, or run history
- Invocation of a shell for `crontab` access, use of `sudo`, or management of another user
- Environment-variable leakage into **Run Now**
- A discrepancy between the command confirmed in the UI and the command executed
- Unsafe handling of CronHarbor metadata or disabled-job markers
- Release artifacts presented as notarized when they are only ad-hoc signed

## Security properties and limits

CronHarbor reads and installs only the current user's crontab through `/usr/bin/crontab`. Applies are serialized and use two pre-install digest checks, a private backup, a secure temporary file, and exact readback. Unknown source stays opaque and byte-preserved. The remaining cross-process race at the final read/install boundary is documented in [docs/SAFETY.md](docs/SAFETY.md).

These controls do not sandbox cron commands. A job can read, modify, delete, or transmit anything available to the user account. **Run Now** also executes user-supplied commands and captures their output locally. Review [docs/SAFETY.md](docs/SAFETY.md) for the complete trust boundary.

CronHarbor currently contains no network client, updater, analytics, or telemetry. That statement does not apply to commands configured by the user.

## Release artifacts

The repository's packaging script supports Developer ID signing and notarization only when the maintainer supplies the corresponding credentials. Its default output is ad-hoc signed. Never treat the default archive as notarized, and never ask users to disable Gatekeeper to install an unverified build.
