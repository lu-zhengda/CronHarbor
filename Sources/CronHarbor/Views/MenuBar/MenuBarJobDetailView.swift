import AppKit
import SwiftUI

struct MenuBarJobDetailView: View {
    @EnvironmentObject private var model: DashboardModel
    let job: JobPresentation
    let onBack: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onReviewChanges: () -> Void
    @State private var confirmsRun = false
    @State private var confirmsDelete = false
    @State private var upcomingRuns: [Date] = []

    var body: some View {
        VStack(spacing: 0) {
            PanelPageHeader(
                title: job.name,
                subtitle: hasPendingChange ? "Staged — not installed" : (job.isEnabled ? "Active" : "Paused"),
                onBack: onBack
            )
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if hasPendingChange {
                        stagedChangesBanner
                    }
                    statusRow
                    scheduleCard
                    commandCard
                    nextRunCard
                    daemonRunCard
                    actionRow

                    let records = model.runHistory.filter { $0.jobID == job.id }
                    if !records.isEmpty {
                        Text("RECENT RUNS")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            ForEach(records.prefix(3)) { record in
                                CompactRunRow(record: record)
                                if record.id != records.prefix(3).last?.id { Divider() }
                            }
                        }
                        .padding(.horizontal, 10)
                        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 10))
                    }

                    Button("Stage Delete…", role: .destructive) {
                        confirmsDelete = true
                    }
                    .disabled(job.diagnostic != nil || model.isSourceBusy)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
                .padding(13)
            }
        }
        .accessibilityIdentifier("cronharbor.menu.job-detail")
        .task(id: job.expression) {
            guard job.isEnabled, job.diagnostic == nil else {
                upcomingRuns = []
                return
            }
            let expression = job.expression
            upcomingRuns = await Task.detached(priority: .userInitiated) {
                ScheduleExpression.upcomingRuns(for: expression, count: 3)
            }.value
        }
        .task { await model.reloadDaemonRuns() }
        .confirmationDialog(
            "Run “\(job.name)” now?",
            isPresented: $confirmsRun,
            titleVisibility: .visible
        ) {
            Button("Run Now") { Task { await model.runNow(job) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(job.runConfirmationMessage)
        }
        .confirmationDialog(
            "Delete “\(job.name)” ?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Stage Deletion", role: .destructive) {
                model.stageDelete(job)
                onBack()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stages a change. Your crontab is not modified until you review and apply it.")
        }
    }

    private var hasPendingChange: Bool {
        model.hasPendingChange(for: job)
    }

    private var stagedChangesBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(CronHarborStyle.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Staged change only")
                    .font(.callout.weight(.semibold))
                Text("The installed crontab is unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Review & Apply", action: onReviewChanges)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(11)
        .background(CronHarborStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("cronharbor.job.staged-warning")
    }

    private var statusRow: some View {
        HStack(spacing: 9) {
            Image(systemName: job.health.symbol)
                .foregroundStyle(CronHarborStyle.statusColor(job.health))
            VStack(alignment: .leading, spacing: 1) {
                Text(job.diagnostic ?? (job.isEnabled ? "Schedule is active" : "Schedule is paused"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(job.diagnostic == nil ? Color.primary : Color.red)
                if job.requiresACPower {
                    Label("Runs on AC power only", systemImage: "powerplug.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(job.isEnabled ? "Pause" : "Enable") {
                model.stageToggle(job)
            }
            .controlSize(.small)
            .disabled(job.diagnostic != nil || model.isSourceBusy)
        }
        .padding(11)
        .background(statusBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private var scheduleCard: some View {
        DetailCard(title: "Schedule", symbol: "calendar.badge.clock") {
            Text(job.scheduleDescription)
                .font(.callout.weight(.semibold))
            Text(job.expression)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var commandCard: some View {
        DetailCard(title: "Command", symbol: "terminal") {
            HStack(alignment: .top, spacing: 8) {
                Text(job.command)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(job.command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy command")
            }
        }
    }

    private var nextRunCard: some View {
        DetailCard(title: "Upcoming runs", symbol: "clock") {
            if let nextRun = upcomingRuns.first ?? job.nextRun, job.isEnabled {
                Text(nextRun, format: .dateTime.weekday(.wide).month().day().hour().minute())
                    .font(.callout.weight(.semibold))
                Text(nextRun, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(upcomingRuns.dropFirst(), id: \.self) { run in
                    Text("then \(run.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(job.isEnabled ? "Not predictable" : "Paused")
                    .font(.callout.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private var daemonRunCard: some View {
        if job.diagnostic == nil {
            DetailCard(title: "Started by cron", symbol: "gearshape.arrow.triangle.2.circlepath") {
                if let event = model.lastDaemonRun(for: job) {
                    Text(event.date.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                        .font(.callout.weight(.semibold))
                    Text("From the system log · start only, exit status is not recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.isLoadingDaemonRuns, model.daemonRuns.isEmpty {
                    Text("Checking the system log…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let daemonRunsError = model.daemonRunsError {
                    Text(daemonRunsError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No recent start observed")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("macOS keeps cron's log entries only briefly. CronHarbor remembers starts it observes while running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .disabled(job.diagnostic != nil || model.isSourceBusy)

            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
            }
            .disabled(job.diagnostic != nil || model.isSourceBusy)
            .help("Stage a copy of this job")

            Button {
                confirmsRun = true
            } label: {
                Label(model.runningJobID == job.id ? "Running…" : "Run Now", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                model.isSourceBusy
                    || model.runningJobID != nil
                    || job.diagnostic != nil
                    || hasPendingChange
            )
            .help(runNowHelp)
        }
    }

    private var runNowHelp: String {
        if model.isSourceBusy { return "Wait for the current crontab operation to finish" }
        if hasPendingChange { return "Apply or discard this job's staged changes first" }
        return "Run this installed command now"
    }

    private var statusBackground: Color {
        if job.diagnostic != nil { return Color.red.opacity(0.08) }
        return CronHarborStyle.statusColor(job.health).opacity(0.08)
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 10))
    }
}
