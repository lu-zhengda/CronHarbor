import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            BackupsSettingsTab()
                .tabItem { Label("Backups", systemImage: "externaldrive.badge.checkmark") }

            SafetySettingsTab()
                .tabItem { Label("Safety", systemImage: "lock.shield") }
        }
        .frame(width: 560, height: 420)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @AppStorage("showsNextRunInMenuBar") private var showsNextRunInMenuBar = false
    @AppStorage("notifyOnRunNowCompletion") private var notifyOnRunNowCompletion = false
    @State private var notificationHint: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch CronHarbor at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, isEnabled in
                        updateLaunchAtLogin(isEnabled)
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Menu Bar") {
                Toggle("Show time until the next run", isOn: $showsNextRunInMenuBar)
                Text("Adds a compact countdown, such as 12m or 3h, next to the CronHarbor icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Notify when a Run Now finishes", isOn: $notifyOnRunNowCompletion)
                    .onChange(of: notifyOnRunNowCompletion) { _, isEnabled in
                        guard isEnabled else {
                            notificationHint = nil
                            return
                        }
                        Task {
                            let granted = await RunNotifier.shared.requestAuthorization()
                            notificationHint = granted
                                ? nil
                                : "macOS notifications are not authorized for CronHarbor. Allow them in System Settings → Notifications."
                        }
                    }
                if let notificationHint {
                    Text(notificationHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Applies only to runs you start from CronHarbor, never to cron's own scheduled runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Safety") {
                Label("Run Now always asks for confirmation", systemImage: "checkmark.shield")
                Label("Every applied change creates a private backup", systemImage: "externaldrive.badge.checkmark")
            }

            Section("Privacy") {
                Text("Everything stays on this Mac. CronHarbor does not use analytics, accounts, or network services.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        let isRegistered = SMAppService.mainApp.status == .enabled
        guard isEnabled != isRegistered else { return }
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "macOS declined the login item change: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Backups

private struct BackupsSettingsTab: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var backupPendingRestore: CrontabBackupInfo?
    @State private var confirmsPrune = false

    private static let keptBackupCount = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crontab backups")
                        .font(.headline)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppSupportPaths.backupsDirectory])
                }
                Button("Delete Old…") {
                    confirmsPrune = true
                }
                .disabled(model.backups.count <= Self.keptBackupCount)
                .help("Keep the \(Self.keptBackupCount) most recent backups and delete the rest")
            }
            .padding(14)

            Divider()

            if model.backups.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "externaldrive")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("No backups yet")
                        .font(.callout.weight(.semibold))
                    Text("CronHarbor saves the exact previous crontab before every applied change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(model.backups) { backup in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.badge.clock")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(backup.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()))
                                .font(.callout)
                            Text(ByteCountFormatStyle().format(Int64(backup.sizeInBytes)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore…") {
                            backupPendingRestore = backup
                        }
                        .controlSize(.small)
                        .disabled(model.isSourceBusy || !model.pendingChanges.isEmpty)
                        .help(
                            model.pendingChanges.isEmpty
                                ? "Install this backup as the current crontab"
                                : "Apply or discard staged changes first"
                        )
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
        .task { model.reloadBackups() }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(
                get: { backupPendingRestore != nil },
                set: { if !$0 { backupPendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Backup", role: .destructive) {
                if let backup = backupPendingRestore {
                    Task { await model.restoreBackup(backup) }
                }
                backupPendingRestore = nil
            }
            Button("Cancel", role: .cancel) { backupPendingRestore = nil }
        } message: {
            if let backup = backupPendingRestore {
                Text("Your crontab will be replaced with the backup from \(backup.createdAt.formatted(.dateTime.month().day().hour().minute())). The current crontab is backed up first, and the write is refused if another app changes it mid-flight.")
            }
        }
        .confirmationDialog(
            "Delete old backups?",
            isPresented: $confirmsPrune,
            titleVisibility: .visible
        ) {
            Button("Delete All but Newest \(Self.keptBackupCount)", role: .destructive) {
                model.pruneBackups(keepingLatest: Self.keptBackupCount)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The \(Self.keptBackupCount) most recent backups are kept. Deleted backups cannot be recovered.")
        }
        .alert(
            "CronHarbor needs attention",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "Unknown error")
        }
    }

    private var summaryText: String {
        guard !model.backups.isEmpty else {
            return "Stored privately in ~/Library/Application Support/CronHarbor/Backups"
        }
        let totalBytes = model.backups.reduce(0) { $0 + $1.sizeInBytes }
        let size = ByteCountFormatStyle().format(Int64(totalBytes))
        return "\(model.backups.count) backups · \(size) · newest first"
    }
}

// MARK: - Safety

private struct SafetySettingsTab: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Current user only", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            Text("CronHarbor invokes /usr/bin/crontab directly for the signed-in user. It never uses sudo, edits system spool files, or manages other users.")
                .foregroundStyle(.secondary)

            Divider()

            Text("Source diagnostics")
                .font(.headline)
            Text(model.diagnostics.isEmpty ? "All detected entries can be displayed safely." : "\(model.diagnostics.count) source lines are protected and preserved exactly.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
