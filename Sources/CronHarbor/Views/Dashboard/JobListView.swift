import SwiftUI

struct JobListView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var pendingRunJob: JobPresentation?

    var body: some View {
        Group {
            if model.filteredJobs.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySymbol)
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if model.jobs.isEmpty {
                        Button("Create First Job") { model.beginCreatingJob() }
                    }
                }
            } else {
                List(model.filteredJobs, selection: $model.selectedJobID) { job in
                    JobRow(job: job)
                        .tag(job.id)
                        .contextMenu {
                            Button("Run Now") {
                                pendingRunJob = job
                            }
                            .disabled(
                                model.runningJobID != nil
                                    || job.diagnostic != nil
                                    || model.hasPendingChange(for: job)
                            )

                            Button(job.isEnabled ? "Pause" : "Enable") {
                                model.stageToggle(job)
                            }
                            .disabled(job.diagnostic != nil)

                            Divider()

                            Button("Edit") { model.beginEditing(job) }
                                .disabled(job.diagnostic != nil)
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(model.selectedFilter.title)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search jobs")
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

    private var emptyTitle: String {
        if !model.searchText.isEmpty { return "No Matches" }
        return model.jobs.isEmpty ? "No Cron Jobs Yet" : "Nothing Here"
    }

    private var emptyDescription: String {
        if !model.searchText.isEmpty { return "Try another name, expression, or command." }
        if model.jobs.isEmpty {
            return "CronHarbor manages only your user crontab. It never needs root access."
        }
        return "No jobs match this filter."
    }

    private var emptySymbol: String {
        model.jobs.isEmpty ? "anchor.circle" : "line.3.horizontal.decrease.circle"
    }
}

private struct JobRow: View {
    let job: JobPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(CronHarborStyle.statusColor(job.health))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityLabel(statusLabel)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(job.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let nextRun = job.nextRun, job.isEnabled {
                        Text(nextRun, style: .relative)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(job.diagnostic ?? job.scheduleDescription)
                    .font(.caption)
                    .foregroundStyle(job.diagnostic == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: String {
        switch job.health {
        case .healthy: "Active"
        case .paused: "Paused"
        case .warning: "Needs attention"
        }
    }
}
