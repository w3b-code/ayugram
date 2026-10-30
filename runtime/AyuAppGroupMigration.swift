import Foundation

/// Import a sideloaded installation's private data into its newly enabled App Group.
/// Copy the complete root, including .tempkey and account metadata, before publishing it.
/// The source and any extension-created bootstrap are retained. A shared account is never merged.
func ayuMigrateLegacyAppGroupData(from privateContainer: URL, to sharedContainer: URL) throws {
    let fileManager = FileManager.default
    let source = privateContainer.appendingPathComponent("telegram-data", isDirectory: true)
    let destination = sharedContainer.appendingPathComponent("telegram-data", isDirectory: true)
    // An import cut short (watchdog, crash, low space) leaves its staging copy, a full database, behind.
    if let entries = try? fileManager.contentsOfDirectory(atPath: sharedContainer.path) {
        for entry in entries where entry.hasPrefix(".ayugram-import-") {
            try? fileManager.removeItem(at: sharedContainer.appendingPathComponent(entry, isDirectory: true))
        }
    }
    guard source.standardizedFileURL != destination.standardizedFileURL,
          fileManager.fileExists(atPath: source.path) else {
        return
    }

    func canReplaceBootstrap() throws -> Bool {
        let sourceEntries = try fileManager.contentsOfDirectory(atPath: source.path)
        guard sourceEntries.contains(where: { $0.hasPrefix("account-") }) else { return false }
        let destinationEntries = try fileManager.contentsOfDirectory(atPath: destination.path)
        // The notification extension can create an empty metadata database before
        // the app's first corrected launch. Its directory alone is not an account.
        let bootstrapEntries: Set<String> = ["accounts-metadata", ".tempkey", ".tempkey.lock", "logs", "temp"]
        return destinationEntries.allSatisfy { bootstrapEntries.contains($0) }
    }

    if fileManager.fileExists(atPath: destination.path), try !canReplaceBootstrap() {
        return
    }

    // Stage on the destination volume so the final rename exposes the entire root at once.
    let staging = sharedContainer.appendingPathComponent(".ayugram-import-" + UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: staging) }
    try fileManager.copyItem(at: source, to: staging)

    if fileManager.fileExists(atPath: destination.path) {
        // Recheck after copying: a newly created shared account must win.
        guard try canReplaceBootstrap() else { return }
        let backup = sharedContainer.appendingPathComponent(".ayugram-bootstrap-" + UUID().uuidString, isDirectory: true)
        try fileManager.moveItem(at: destination, to: backup)
        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.moveItem(at: backup, to: destination)
            throw error
        }
    } else {
        try fileManager.moveItem(at: staging, to: destination)
    }
}
