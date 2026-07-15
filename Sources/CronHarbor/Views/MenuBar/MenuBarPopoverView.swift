import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var pendingRunJob: JobPresentation?
    private let upcomingRunTimer = Timer.publish(
        every: 60,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if let nextJob = model.nextJobs.first {
                nextJobCard(nextJob)
            } else {
                noJobsCard
            }

            Divider()

            VStack(spacing: 2) {
                MenuActionRow(title: "Open CronHarbor", symbol: "macwindow", shortcut: nil) {
                    showDashboard()
                }
                MenuActionRow(
                    title: "New Job",
                    symbol: "plus",
                    shortcut: "⌘N",
                    isDisabled: model.isSourceBusy
                ) {
                    showDashboard()
                    model.beginCreatingJob()
                }
                MenuActionRow(
                    title: "Refresh",
                    symbol: "arrow.clockwise",
                    shortcut: "⌘R",
                    isDisabled: model.isSourceBusy || !model.pendingChanges.isEmpty
                ) {
                    Task { await model.refresh() }
                }
                MenuActionRow(title: "Settings", symbol: "gearshape", shortcut: "⌘,") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .padding(8)

            Divider()

            HStack {
                Text("CronHarbor runs locally")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(12)
        }
        .frame(width: 370)
        .background(.regularMaterial)
        .task {
            if model.jobs.isEmpty { await model.refresh() }
            model.refreshUpcomingRuns()
        }
        .onReceive(upcomingRunTimer) { now in
            model.refreshUpcomingRuns(at: now)
        }
        .confirmationDialog(
            pendingRunJob.map { "Run “\($0.name)” now?" } ?? "Run this job now?",
            isPresented: Binding(
                get: { pendingRunJob != nil },
                set: { if !$0 { pendingRunJob = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let job = pendingRunJob {
                Button("Run Now") {
                    pendingRunJob = nil
                    Task { await model.runNow(job) }
                }
            }
            Button("Cancel", role: .cancel) { pendingRunJob = nil }
        } message: {
            if let job = pendingRunJob {
                Text(job.runConfirmationMessage)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "anchor.circle.fill")
                .font(.title)
                .foregroundStyle(CronHarborStyle.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("CronHarbor")
                    .font(.headline)
                Text(model.healthSummary)
                    .font(.caption)
                    .foregroundStyle(model.attentionCount == 0 ? CronHarborStyle.success : .red)
            }

            Spacer()

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: model.attentionCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.attentionCount == 0 ? CronHarborStyle.success : .red)
            }
        }
        .padding(16)
    }

    private func nextJobCard(_ job: JobPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEXT JOB")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .font(.title2)
                    .foregroundStyle(CronHarborStyle.accent)
                    .frame(width: 34, height: 34)
                    .background(CronHarborStyle.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if let nextRun = job.nextRun {
                        Text(nextRun, style: .relative)
                            .font(.callout)
                        Text(nextRun, format: .dateTime.weekday(.abbreviated).hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    pendingRunJob = job
                } label: {
                    Image(systemName: model.runningJobID == job.id ? "hourglass" : "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(
                    model.isSourceBusy
                        || model.runningJobID != nil
                        || model.hasPendingChange(for: job)
                )
                .help(model.hasPendingChange(for: job) ? "Apply or discard this job’s pending changes first" : "Run now")
            }
        }
        .padding(16)
    }

    private var noJobsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No upcoming jobs", systemImage: "moon.stars")
                .font(.body.weight(.medium))
            Text(model.jobs.isEmpty ? "Create your first user cron job." : "Enable a job to see its next run here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func showDashboard() {
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }

}

private struct MenuActionRow: View {
    let title: String
    let symbol: String
    let shortcut: String?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
