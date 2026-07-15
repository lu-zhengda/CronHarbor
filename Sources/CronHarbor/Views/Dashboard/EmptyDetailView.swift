import SwiftUI

struct EmptyDetailView: View {
    @EnvironmentObject private var model: DashboardModel
    let hasJobs: Bool

    var body: some View {
        ContentUnavailableView {
            Label(hasJobs ? "Select a Job" : "Welcome to CronHarbor", systemImage: "anchor.circle")
        } description: {
            Text(hasJobs
                ? "Choose a cron job to inspect its schedule, command, and next run."
                : "Manage your user cron jobs without editing crontab by hand. Every write is explicit, backed up, and verified.")
        } actions: {
            if !hasJobs {
                Button("Create First Job") { model.beginCreatingJob() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
