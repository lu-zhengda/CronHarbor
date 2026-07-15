import AppKit
import SwiftUI

struct MenuBarJobsView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.openSettings) private var openSettings

    let onSelectJob: (JobPresentation) -> Void
    let onCreateJob: () -> Void
    let onReviewChanges: () -> Void
    let onShowHistory: () -> Void
    @State private var confirmsQuit = false

    var body: some View {
        VStack(spacing: 0) {
            rootHeader

            Divider()

            if let nextJob = model.installedNextJobs.first {
                NextJobSummary(
                    job: nextJob,
                    onOpen: {
                        if model.hasPendingChange(for: nextJob),
                           !model.jobs.contains(where: { $0.id == nextJob.id })
                        {
                            onReviewChanges()
                        } else {
                            onSelectJob(nextJob)
                        }
                    },
                    onRun: { Task { await model.runNow(nextJob) } }
                )
            } else {
                noUpcomingJob
            }

            Divider()

            searchAndFilters

            jobList

            if !model.pendingChanges.isEmpty {
                Divider()
                pendingChangesBar
            }

            Divider()
            footer
        }
        .accessibilityIdentifier("cronharbor.menu.jobs")
        .confirmationDialog(
            "Quit and discard staged changes?",
            isPresented: $confirmsQuit,
            titleVisibility: .visible
        ) {
            Button("Quit and Discard", role: .destructive) {
                NSApp.terminate(nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your installed crontab will remain unchanged.")
        }
    }

    private var rootHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(CronHarborStyle.accent, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
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
                    .frame(width: 26, height: 26)
            } else {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(model.isSourceBusy || !model.pendingChanges.isEmpty || model.isEditorPresented)
                .help(model.pendingChanges.isEmpty ? "Reload the installed crontab" : "Review pending changes first")
                .accessibilityIdentifier("cronharbor.refresh")
            }

            Button(action: onCreateJob) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.white)
                    .background(CronHarborStyle.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.isSourceBusy || model.isEditorPresented)
            .help("New cron job")
            .accessibilityIdentifier("cronharbor.new-job")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var noUpcomingJob: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary.opacity(0.7), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("No upcoming job")
                    .font(.callout.weight(.semibold))
                Text(noUpcomingJobMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var noUpcomingJobMessage: String {
        if !model.hasInstalledJobs, !model.pendingChanges.isEmpty {
            return "Apply your staged changes to schedule the first job."
        }
        if !model.hasInstalledJobs {
            return "Create your first cron job."
        }
        return "No installed job has a predictable upcoming run."
    }

    private var searchAndFilters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search jobs or commands", text: $model.searchText)
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 5) {
                FilterChip(filter: .all, shortTitle: "All")
                FilterChip(filter: .active, shortTitle: "Active")
                FilterChip(filter: .paused, shortTitle: "Paused")
                FilterChip(filter: .attention, shortTitle: "Issues")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var jobList: some View {
        if model.filteredJobs.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: model.jobs.isEmpty ? "calendar.badge.plus" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(model.jobs.isEmpty ? "No cron jobs yet" : "No matching jobs")
                    .font(.callout.weight(.semibold))
                Text(model.jobs.isEmpty ? "Use + to stage your first job." : "Try another search or filter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.filteredJobs) { job in
                        MenuBarJobRow(
                            job: job,
                            hasPendingChange: model.hasPendingChange(for: job),
                            isBusy: model.isSourceBusy,
                            onOpen: { onSelectJob(job) },
                            onToggle: { model.stageToggle(job) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }

    private var pendingChangesBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(CronHarborStyle.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.pendingChanges.count) staged \(model.pendingChanges.count == 1 ? "change" : "changes")")
                    .font(.callout.weight(.semibold))
                Text("Your crontab is unchanged")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Review & Apply", action: onReviewChanges)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("cronharbor.review-changes")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(CronHarborStyle.accent.opacity(0.07))
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button(action: onShowHistory) {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("cronharbor.history")

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("cronharbor.settings")

            Spacer()

            Button("Quit") {
                if model.pendingChanges.isEmpty {
                    NSApp.terminate(nil)
                } else {
                    confirmsQuit = true
                }
            }
                .accessibilityIdentifier("cronharbor.quit")
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 36)
    }
}

private struct NextJobSummary: View {
    @EnvironmentObject private var model: DashboardModel
    let job: JobPresentation
    let onOpen: () -> Void
    let onRun: () -> Void
    @State private var confirmsRun = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(CronHarborStyle.accent)
                        .frame(width: 30, height: 30)
                        .background(CronHarborStyle.accent.opacity(0.11), in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(isPendingDeletion ? "UP NEXT · DELETE STAGED" : "UP NEXT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(job.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        if let nextRun = job.nextRun {
                            Text("\(nextRun.formatted(.dateTime.weekday(.abbreviated).hour().minute())) · \(nextRun.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                confirmsRun = true
            } label: {
                Image(systemName: model.runningJobID == job.id ? "hourglass" : "play.fill")
                    .frame(width: 30, height: 26)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isSourceBusy || model.runningJobID != nil || model.hasPendingChange(for: job))
            .help(model.hasPendingChange(for: job) ? "Apply or discard this job's staged changes first" : "Run now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .confirmationDialog(
            "Run “\(job.name)” now?",
            isPresented: $confirmsRun,
            titleVisibility: .visible
        ) {
            Button("Run Now", action: onRun)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(job.runConfirmationMessage)
        }
    }

    private var isPendingDeletion: Bool {
        model.hasPendingChange(for: job)
            && !model.jobs.contains(where: { $0.id == job.id })
    }
}

private struct FilterChip: View {
    @EnvironmentObject private var model: DashboardModel
    let filter: SidebarFilter
    let shortTitle: String

    var body: some View {
        Button {
            model.selectedFilter = filter
        } label: {
            HStack(spacing: 4) {
                Text(shortTitle)
                Text("\(model.count(for: filter))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(model.selectedFilter == filter ? .white.opacity(0.8) : .secondary)
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .frame(height: 25)
            .foregroundStyle(model.selectedFilter == filter ? .white : .primary)
            .background(
                model.selectedFilter == filter ? CronHarborStyle.accent : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cronharbor.filter.\(filter.rawValue)")
    }
}

private struct MenuBarJobRow: View {
    let job: JobPresentation
    let hasPendingChange: Bool
    let isBusy: Bool
    let onOpen: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onOpen) {
                HStack(spacing: 9) {
                    Image(systemName: job.health.symbol)
                        .font(.body)
                        .foregroundStyle(CronHarborStyle.statusColor(job.health))
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(job.name)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            if hasPendingChange {
                                Text("STAGED")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(CronHarborStyle.accent)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(CronHarborStyle.accent.opacity(0.11), in: Capsule())
                            }
                        }
                        Text(rowSubtitle)
                            .font(.caption)
                            .foregroundStyle(job.diagnostic == nil ? Color.secondary : Color.red)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cronharbor.job.\(job.id)")

            Button(action: onToggle) {
                Image(systemName: job.isEnabled ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.semibold))
                    .frame(width: 27, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(job.isEnabled ? .secondary : CronHarborStyle.success)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
            .disabled(job.diagnostic != nil || isBusy)
            .help(job.isEnabled ? "Stage pause" : "Stage enable")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 9))
    }

    private var rowSubtitle: String {
        if let diagnostic = job.diagnostic { return diagnostic }
        if let nextRun = job.nextRun, job.isEnabled {
            return "\(job.scheduleDescription) · \(nextRun.formatted(.relative(presentation: .named)))"
        }
        return job.isEnabled ? job.scheduleDescription : "Paused · \(job.scheduleDescription)"
    }
}
