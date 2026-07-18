import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var page: MenuBarPage = .jobs
    private let upcomingRunTimer = Timer.publish(
        every: 60,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        Group {
            switch page {
            case .jobs:
                MenuBarJobsView(
                    onSelectJob: showJob,
                    onCreateJob: createJob,
                    onReviewChanges: { page = .changes },
                    onShowHistory: { page = .history }
                )
            case .job(let id):
                if let job = model.jobs.first(where: { $0.id == id }) {
                    MenuBarJobDetailView(
                        job: job,
                        onBack: { page = .jobs },
                        onEdit: { editJob(job) },
                        onDuplicate: { duplicateJob(job) },
                        onReviewChanges: { page = .changes }
                    )
                } else {
                    MenuMissingJobView { page = .jobs }
                }
            case .editor(let returnJobID):
                if model.editorDraft != nil {
                    JobEditorView(
                        draft: editorDraftBinding,
                        onCancel: {
                            model.cancelEditing()
                            returnFromEditor(to: returnJobID)
                        },
                        onSave: { draft in
                            let jobID = model.stage(draft)
                            if let jobID {
                                page = .job(jobID)
                            } else {
                                page = .jobs
                            }
                        }
                    )
                } else {
                    MenuMissingJobView { page = .jobs }
                }
            case .changes:
                PendingChangesReviewView { page = .jobs }
            case .history:
                MenuBarHistoryView { page = .jobs }
            }
        }
        .frame(width: 430, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if model.jobs.isEmpty, model.pendingChanges.isEmpty {
                await model.refresh()
            }
            model.refreshUpcomingRuns()
            if let draft = model.editorDraft {
                page = .editor(returnJobID: draft.id)
            }
        }
        .onReceive(upcomingRunTimer) { now in
            model.refreshUpcomingRuns(at: now)
        }
        .onChange(of: model.jobs.map(\.id)) { _, ids in
            guard case .job(let id) = page, !ids.contains(id) else { return }
            page = .jobs
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

    private var editorDraftBinding: Binding<JobDraft> {
        Binding(
            get: { model.editorDraft ?? JobDraft() },
            set: { model.editorDraft = $0 }
        )
    }

    private func showJob(_ job: JobPresentation) {
        model.selectedJobID = job.id
        page = .job(job.id)
    }

    private func createJob() {
        model.beginCreatingJob()
        guard model.editorDraft != nil else { return }
        page = .editor(returnJobID: nil)
    }

    private func editJob(_ job: JobPresentation) {
        model.beginEditing(job)
        guard model.editorDraft != nil else { return }
        page = .editor(returnJobID: job.id)
    }

    private func duplicateJob(_ job: JobPresentation) {
        model.beginDuplicating(job)
        guard model.editorDraft != nil else { return }
        page = .editor(returnJobID: job.id)
    }

    private func returnFromEditor(to jobID: String?) {
        if let jobID, model.jobs.contains(where: { $0.id == jobID }) {
            page = .job(jobID)
        } else {
            page = .jobs
        }
    }
}

private enum MenuBarPage: Equatable {
    case jobs
    case job(String)
    case editor(returnJobID: String?)
    case changes
    case history
}

struct PanelPageHeader: View {
    let title: String
    let subtitle: String?
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .background(.quaternary.opacity(0.65), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 13)
        .frame(height: 56)
    }
}

private struct MenuMissingJobView: View {
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "questionmark.folder")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("This job is no longer available")
                .font(.headline)
            Button("Back to Jobs", action: onBack)
            Spacer()
        }
    }
}
