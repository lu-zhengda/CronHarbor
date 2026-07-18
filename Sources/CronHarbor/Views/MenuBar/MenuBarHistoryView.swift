import AppKit
import SwiftUI

struct MenuBarHistoryView: View {
    @EnvironmentObject private var model: DashboardModel
    let onBack: () -> Void
    @State private var source: HistorySource = .runNow
    @State private var showsFailuresOnly = false
    @State private var confirmsClear = false

    private enum HistorySource: Hashable {
        case runNow
        case daemon
    }

    private var visibleRecords: [RunRecord] {
        showsFailuresOnly ? model.runHistory.filter { !$0.succeeded } : model.runHistory
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelPageHeader(
                title: "Run History",
                subtitle: source == .runNow
                    ? "Commands started with Run Now"
                    : "Cron daemon starts from the system log",
                onBack: onBack
            )
            Divider()

            Picker("Source", selection: $source) {
                Text("Run Now").tag(HistorySource.runNow)
                Text("Scheduled").tag(HistorySource.daemon)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            Divider()

            switch source {
            case .runNow:
                runNowHistory
            case .daemon:
                daemonHistory
            }
        }
        .accessibilityIdentifier("cronharbor.menu.history")
        .task(id: source) {
            if source == .daemon {
                await model.reloadDaemonRuns()
            }
        }
        .confirmationDialog(
            "Clear all Run Now history?",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                Task { await model.clearRunHistory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the recorded output of runs CronHarbor started. Your crontab is not affected.")
        }
    }

    @ViewBuilder
    private var runNowHistory: some View {
        if !model.runHistory.isEmpty {
            HStack(spacing: 8) {
                Toggle("Failures only", isOn: $showsFailuresOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("Clear History") {
                    confirmsClear = true
                }
                .controlSize(.small)
                .disabled(model.isSourceBusy)
                .accessibilityIdentifier("cronharbor.history.clear")
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            Divider()
        }

        if model.runHistory.isEmpty {
            emptyState(
                title: "No CronHarbor runs yet",
                message: "Runs you start with Run Now are recorded here."
            )
        } else if visibleRecords.isEmpty {
            emptyState(
                title: "No failed runs",
                message: "Every recorded run exited with status 0."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleRecords) { record in
                        CompactRunRow(record: record, showsJobName: true)
                        Divider()
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private var daemonHistory: some View {
        if model.isLoadingDaemonRuns, model.daemonRuns.isEmpty {
            VStack {
                Spacer()
                ProgressView("Reading the system log…")
                    .controlSize(.small)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let daemonRunsError = model.daemonRunsError, model.daemonRuns.isEmpty {
            emptyState(title: "System log unavailable", message: daemonRunsError)
        } else if model.daemonRuns.isEmpty {
            emptyState(
                title: "No scheduled starts observed",
                message: "macOS keeps cron's log entries only briefly. Starts observed while CronHarbor is running accumulate here."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.daemonRuns) { event in
                        DaemonRunRow(
                            event: event,
                            jobName: model.jobName(forDaemonCommand: event.command)
                        )
                        Divider()
                    }
                }
                .padding(.horizontal, 12)
            }
            Divider()
            Text("Starts observed in the system log. macOS cron does not record completion or exit status.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 9) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DaemonRunRow: View {
    let event: DaemonRunEvent
    let jobName: String?

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "gearshape.arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(jobName ?? event.command)
                    .font(jobName == nil ? .system(.caption, design: .monospaced) : .callout.weight(.medium))
                    .lineLimit(1)
                Text("Started \(event.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · \(event.date.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .help(event.command)
    }
}

struct CompactRunRow: View {
    let record: RunRecord
    var showsJobName = false

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if record.standardOutput.isEmpty, record.standardError.isEmpty {
                    Text("This run produced no captured output.")
                        .foregroundStyle(.secondary)
                }
                if !record.standardOutput.isEmpty {
                    output(title: "Standard Output", value: record.standardOutput)
                }
                if !record.standardError.isEmpty {
                    output(title: "Standard Error", value: record.standardError)
                }
            }
            .font(.caption)
            .padding(.vertical, 8)
            .padding(.leading, 24)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(record.succeeded ? CronHarborStyle.success : .red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(showsJobName ? record.jobName : (record.succeeded ? "Completed" : "Failed"))
                        .font(.callout.weight(.medium))
                    Text("\(record.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · exit \(record.exitCode) · \(record.duration.formatted(.number.precision(.fractionLength(1))))s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func output(title: String, value: String) -> some View {
        let preview = displayText(value)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
                .buttonStyle(.borderless)
                .font(.caption2)
            }
            Text(preview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func displayText(_ value: String) -> String {
        let displayLimit = 20_000
        guard value.count > displayLimit else { return value }
        return String(value.prefix(displayLimit))
            + "\n[Display shortened. Copy to get all retained output.]"
    }
}
