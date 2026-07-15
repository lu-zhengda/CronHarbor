import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        TabView {
            Form {
                Section("Menu Bar") {
                    LabeledContent("Upcoming job") {
                        Text("Shown when predictable")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Safety") {
                    Label("Run Now always asks for confirmation", systemImage: "checkmark.shield")
                    Label("Every applied change creates a private backup", systemImage: "externaldrive.badge.checkmark")
                }

                Section("Privacy") {
                    Text("Everything stays on this Mac. CronHarbor does not use analytics, accounts, or network services.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            VStack(alignment: .leading, spacing: 14) {
                Label("Current user only", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline)
                Text("CronHarbor invokes /usr/bin/crontab directly for the signed-in user. It never uses sudo, edits system spool files, or manages other users.")
                    .foregroundStyle(.secondary)

                Divider()

                Text("Source diagnostics")
                    .font(.headline)
                Text(model.diagnostics.isEmpty ? "All detected entries can be displayed safely." : "\(model.diagnostics.count) source lines are protected and preserved exactly.")
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(24)
            .tabItem { Label("Safety", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 350)
    }
}
