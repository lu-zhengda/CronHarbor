import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        List(selection: $model.selectedFilter) {
            Section("Jobs") {
                ForEach(SidebarFilter.allCases.filter { $0 != .history }) { filter in
                    SidebarRow(filter: filter, count: model.count(for: filter))
                        .tag(filter)
                }
            }

            Section("Activity") {
                SidebarRow(filter: .history, count: model.count(for: .history))
                    .tag(SidebarFilter.history)
            }

            if !model.diagnostics.isEmpty {
                Section("Source") {
                    Label("\(model.diagnostics.count) preserved lines", systemImage: "doc.badge.ellipsis")
                        .foregroundStyle(.secondary)
                        .help("CronHarbor preserves lines it cannot safely edit.")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    model.beginCreatingJob()
                } label: {
                    Label("New Job", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(12)
        }
    }
}

private struct SidebarRow: View {
    let filter: SidebarFilter
    let count: Int

    var body: some View {
        HStack {
            Label(filter.title, systemImage: filter.symbol)
                .symbolRenderingMode(.hierarchical)
            Spacer()
            Text(count, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
    }
}
