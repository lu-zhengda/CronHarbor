import AppKit
import SwiftUI

struct MenuBarHistoryView: View {
    @EnvironmentObject private var model: DashboardModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelPageHeader(
                title: "Run History",
                subtitle: "Only commands started with Run Now",
                onBack: onBack
            )
            Divider()

            if model.runHistory.isEmpty {
                VStack(spacing: 9) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No CronHarbor runs yet")
                        .font(.headline)
                    Text("Scheduled cron executions are not tracked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.runHistory) { record in
                            CompactRunRow(record: record, showsJobName: true)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .accessibilityIdentifier("cronharbor.menu.history")
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
