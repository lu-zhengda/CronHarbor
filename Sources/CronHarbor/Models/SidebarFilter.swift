import Foundation

enum SidebarFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case paused
    case attention
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Jobs"
        case .active: "Active"
        case .paused: "Paused"
        case .attention: "Needs Attention"
        case .history: "Run History"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .active: "play.circle.fill"
        case .paused: "pause.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .history: "clock.arrow.circlepath"
        }
    }
}
