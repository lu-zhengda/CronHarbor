import SwiftUI

enum CronHarborStyle {
    static let accent = Color(red: 0.12, green: 0.43, blue: 0.88)
    static let success = Color(red: 0.10, green: 0.63, blue: 0.36)
    static let warning = Color(red: 0.95, green: 0.58, blue: 0.08)

    static func statusColor(_ health: JobHealth) -> Color {
        switch health {
        case .healthy: success
        case .paused: warning
        case .warning: .red
        }
    }
}
