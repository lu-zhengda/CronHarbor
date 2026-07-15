import AppKit
import SwiftUI

struct PendingChangesReviewView: View {
    @EnvironmentObject private var model: DashboardModel
    let onDone: () -> Void
    @State private var confirmsApply = false
    @State private var confirmsDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            PanelPageHeader(
                title: "Review Changes",
                subtitle: "Nothing is installed until you apply",
                onBack: onDone
            )
            Divider()

            if model.pendingChanges.isEmpty {
                VStack(spacing: 9) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(CronHarborStyle.success)
                    Text("No staged changes")
                        .font(.headline)
                    Button("Back to Jobs", action: onDone)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(model.pendingChanges.enumerated()), id: \.offset) { _, change in
                            PendingChangeRow(change: change)
                        }

                        Label(
                            "CronHarbor rechecks the complete crontab before writing and stops if it changed elsewhere.",
                            systemImage: "lock.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                    }
                    .padding(12)
                }

                Divider()
                HStack(spacing: 10) {
                    Button("Discard All", role: .destructive) {
                        confirmsDiscard = true
                    }
                    .disabled(model.isSourceBusy)

                    Spacer()

                    if model.isApplying {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button("Apply \(model.pendingChanges.count) \(model.pendingChanges.count == 1 ? "Change" : "Changes")") {
                        confirmsApply = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSourceBusy)
                    .accessibilityIdentifier("cronharbor.apply-changes")
                }
                .padding(12)
            }
        }
        .accessibilityIdentifier("cronharbor.menu.changes")
        .confirmationDialog(
            "Apply these changes to your crontab?",
            isPresented: $confirmsApply,
            titleVisibility: .visible
        ) {
            Button("Apply Changes") {
                Task {
                    await model.applyPendingChanges()
                    if model.pendingChanges.isEmpty { onDone() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("CronHarbor will create a private backup before installing the reviewed result.")
        }
        .confirmationDialog(
            "Discard every staged change?",
            isPresented: $confirmsDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard All", role: .destructive) {
                Task {
                    await model.discardPendingChanges()
                    if model.pendingChanges.isEmpty { onDone() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your installed crontab will remain unchanged.")
        }
    }
}

private struct PendingChangeRow: View {
    let change: JobChange

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("\(action) \(name)")
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Exact command") {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(command)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    .padding(.top, 6)
                }
                .font(.caption)
            }
            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
    }

    private var action: String {
        switch change {
        case .create: "Create"
        case .update: "Update"
        case .delete: "Delete"
        }
    }

    private var name: String {
        switch change {
        case .create(_, let draft), .update(_, let draft): draft.name
        case .delete(_, let snapshot): snapshot.name
        }
    }

    private var detail: String {
        switch change {
        case .create(_, let draft), .update(_, let draft):
            "\(draft.isEnabled ? "Active" : "Paused") · \(powerDescription(draft.requiresACPower)) · \(draft.expression)"
        case .delete(_, let snapshot):
            "Delete installed \(snapshot.isEnabled ? "active" : "paused") job · \(powerDescription(snapshot.requiresACPower)) · \(snapshot.expression)"
        }
    }

    private var command: String {
        switch change {
        case .create(_, let draft), .update(_, let draft): draft.command
        case .delete(_, let snapshot): snapshot.command
        }
    }

    private var symbol: String {
        switch change {
        case .create: "plus"
        case .update: "pencil"
        case .delete: "trash"
        }
    }

    private var tint: Color {
        if case .delete = change { return .red }
        return CronHarborStyle.accent
    }

    private func powerDescription(_ requiresACPower: Bool) -> String {
        requiresACPower ? "AC power only" : "Any power source"
    }
}
