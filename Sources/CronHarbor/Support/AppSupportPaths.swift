import Foundation

/// Canonical locations for CronHarbor's private on-disk state.
enum AppSupportPaths {
    static var cronHarborDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("CronHarbor", isDirectory: true)
    }

    static var backupsDirectory: URL {
        cronHarborDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    static var runHistoryFile: URL {
        cronHarborDirectory.appendingPathComponent("run-history.json")
    }
}
