import AppKit
import SwiftUI

struct JobDetailView: View {
    @EnvironmentObject private var model: DashboardModel
    let job: JobPresentation

    @State private var selectedSection = DetailSection.overview
    @State private var confirmsRun = false
    @State private var confirmsDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                Picker("Section", selection: $selectedSection) {
                    ForEach(DetailSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch selectedSection {
                case .overview:
                    overview
                case .schedule:
                    schedule
                case .history:
                    history
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
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
            "Delete “\(job.name)”?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Stage Deletion", role: .destructive) { model.stageDelete(job) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stages a change. Your crontab is not modified until you review and apply pending changes.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: job.health.symbol)
                .font(.title)
                .foregroundStyle(CronHarborStyle.statusColor(job.health))

            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)
                HStack(spacing: 7) {
                    Text(job.isEnabled ? "Active" : "Paused")
                    if job.requiresACPower {
                        Text("·")
                        Label("AC power only", systemImage: "powerplug.fill")
                    }
                    if !job.isManaged {
                        Text("·")
                        Text("Imported")
                    }
                    if let diagnostic = job.diagnostic {
                        Text("·")
                        Text(diagnostic)
                            .foregroundStyle(.red)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Enabled", isOn: Binding(
                get: { job.isEnabled },
                set: { _ in model.stageToggle(job) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(job.diagnostic != nil || model.isSourceBusy)
            .help(job.isEnabled ? "Pause this job" : "Enable this job")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            detailCard(title: "Schedule", symbol: "calendar.badge.clock") {
                Text(job.scheduleDescription)
                    .font(.title3.weight(.semibold))
                Text(job.expression)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            detailCard(title: "Command", symbol: "terminal") {
                HStack(alignment: .top) {
                    Text(job.command)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(job.command, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy command")
                }
            }

            detailCard(title: "Next Run", symbol: "clock") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        if let nextRun = job.nextRun, job.isEnabled {
                            Text(nextRun, format: .dateTime.weekday(.wide).month().day().hour().minute())
                                .font(.title3.weight(.semibold))
                            Text(nextRun, style: .relative)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(job.isEnabled ? "Not predictable" : "Paused")
                                .font(.title3.weight(.semibold))
                            Text(job.isEnabled ? "Some cron shortcuts do not have a deterministic next time." : "Enable this job to calculate its next run.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        confirmsRun = true
                    } label: {
                        Label(model.runningJobID == job.id ? "Running…" : "Run Now", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.runningJobID != nil
                            || job.diagnostic != nil
                            || model.hasPendingChange(for: job)
                    )
                    .help(
                        model.hasPendingChange(for: job)
                            ? "Apply or discard this job’s pending changes first"
                            : "Run this job now"
                    )
                }
            }

            HStack {
                Button("Edit Job…") { model.beginEditing(job) }
                    .disabled(job.diagnostic != nil || model.isSourceBusy)
                Spacer()
                Button("Delete Job…", role: .destructive) { confirmsDelete = true }
                    .disabled(job.diagnostic != nil || model.isSourceBusy)
            }
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exact cron expression")
                .font(.headline)
            Text(job.expression)
                .font(.system(.title3, design: .monospaced).weight(.medium))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .textSelection(.enabled)

            Text("CronHarbor calculates upcoming times locally. macOS cron does not catch up executions missed while your Mac is asleep.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var history: some View {
        let records = model.runHistory.filter { $0.jobID == job.id }
        return Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "No CronHarbor Runs",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("This history includes only runs started with Run Now. CronHarbor does not claim visibility into executions started by cron.")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(records) { record in
                        RunHistoryRow(record: record)
                        Divider()
                    }
                }
            }
        }
    }

    private func detailCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct RunHistoryRow: View {
    let record: RunRecord

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                if record.standardOutput.isEmpty, record.standardError.isEmpty {
                    Text("This run produced no captured output.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    if !record.standardOutput.isEmpty {
                        outputSection(title: "Standard Output", text: record.standardOutput)
                    }
                    if !record.standardError.isEmpty {
                        outputSection(title: "Standard Error", text: record.standardError)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.leading, 30)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(record.succeeded ? CronHarborStyle.success : .red)
                VStack(alignment: .leading) {
                    Text(record.succeeded ? "Succeeded" : "Failed (exit \(record.exitCode))")
                        .font(.body.weight(.medium))
                    Text(record.startedAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.duration, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                Text("s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    private func outputSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Text(displayText(text))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func displayText(_ text: String) -> String {
        let displayLimit = 20_000
        guard text.count > displayLimit else { return text }
        return String(text.prefix(displayLimit)) + "\n[Display shortened. Copy to get all retained output.]"
    }
}

private enum DetailSection: String, CaseIterable, Identifiable {
    case overview
    case schedule
    case history

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
