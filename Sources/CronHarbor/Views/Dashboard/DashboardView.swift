import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.openSettings) private var openSettings
    private let upcomingRunTimer = Timer.publish(
        every: 60,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if !model.pendingChanges.isEmpty {
                PendingChangesBar()
            }

            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 250)
            } content: {
                JobListView()
                    .navigationSplitViewColumnWidth(min: 290, ideal: 340, max: 430)
            } detail: {
                if let job = model.selectedJob {
                    JobDetailView(job: job)
                        .id(job.id)
                } else {
                    EmptyDetailView(hasJobs: !model.jobs.isEmpty)
                }
            }
            .navigationSplitViewStyle(.balanced)
            .disabled(model.isSourceBusy)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isSourceBusy || !model.pendingChanges.isEmpty)
                .help(
                    model.pendingChanges.isEmpty
                        ? "Reload the installed crontab"
                        : "Apply or discard pending changes before refreshing"
                )

                Button {
                    model.beginCreatingJob()
                } label: {
                    Label("New Job", systemImage: "plus")
                }
                .disabled(model.isSourceBusy)
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $model.isEditorPresented) {
            if let draft = model.editorDraft {
                JobEditorView(draft: draft) { savedDraft in
                    model.stage(savedDraft)
                }
            }
        }
        .task {
            model.refreshUpcomingRuns()
        }
        .onReceive(upcomingRunTimer) { now in
            model.refreshUpcomingRuns(at: now)
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
}

private struct PendingChangesBar: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var confirmsApply = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(CronHarborStyle.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.pendingChanges.count) pending \(model.pendingChanges.count == 1 ? "change" : "changes")")
                    .font(.callout.weight(.semibold))
                Text("Your crontab has not been changed yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Discard") {
                Task { await model.discardPendingChanges() }
            }
            .disabled(model.isApplying)

            Button("Review & Apply") {
                confirmsApply = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isApplying)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .confirmationDialog(
            "Apply \(model.pendingChanges.count) changes to your crontab?",
            isPresented: $confirmsApply,
            titleVisibility: .visible
        ) {
            Button("Apply Changes") {
                Task { await model.applyPendingChanges() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("CronHarbor will check for external edits, create a private backup, install the updated crontab, and verify the result.")
        }
    }
}
