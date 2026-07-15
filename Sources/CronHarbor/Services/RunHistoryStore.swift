import Foundation

actor RunHistoryStore {
    private let fileURL: URL
    private let maximumRecords: Int

    init(fileURL: URL, maximumRecords: Int = 100) {
        self.fileURL = fileURL
        self.maximumRecords = maximumRecords
    }

    func load() -> [RunRecord] {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) {
            // Repair permissions left by an older version even when this
            // launch only reads history.
            try? preparePrivateStorage(using: fileManager)
        }

        return loadRecords()
    }

    func append(_ record: RunRecord) throws {
        let fileManager = FileManager.default
        try preparePrivateStorage(using: fileManager)

        var records = loadRecords()
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        records = Array(records.prefix(maximumRecords))

        let data = try JSONEncoder().encode(records)
        try writeAtomicallyAndPrivately(data, using: fileManager)
    }

    private func loadRecords() -> [RunRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([RunRecord].self, from: data)
        else {
            return []
        }
        return Array(records.sorted(by: { $0.startedAt > $1.startedAt }).prefix(maximumRecords))
    }

    private func preparePrivateStorage(using fileManager: FileManager) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        // createDirectory's attributes apply only when the last component is
        // new. Explicitly restrict a pre-existing application-support folder.
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directoryURL.path
        )

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: fileURL.path
            )
        }
    }

    private func writeAtomicallyAndPrivately(
        _ data: Data,
        using fileManager: FileManager
    ) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: data,
            attributes: [.posixPermissions: NSNumber(value: 0o600)]
        ) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileWriteUnknown.rawValue,
                userInfo: [NSFilePathErrorKey: temporaryURL.path]
            )
        }

        // Reinforce the mode before the rename. The containing directory is
        // already 0700, and the completed private file replaces the old file
        // in one same-directory operation.
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: temporaryURL.path
        )

        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(
                fileURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }

        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fileURL.path
        )
    }
}
