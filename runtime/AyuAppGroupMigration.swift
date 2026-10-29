import Foundation

/// Import a sideloaded installation's private data into its newly enabled App Group.
/// Copy the complete root, including .tempkey and account metadata, before publishing it.
/// The source is retained and an existing shared root is never overwritten or merged.
func ayuMigrateLegacyAppGroupData(from privateContainer: URL, to sharedContainer: URL) throws {
    let fileManager = FileManager.default
    let source = privateContainer.appendingPathComponent("telegram-data", isDirectory: true)
    let destination = sharedContainer.appendingPathComponent("telegram-data", isDirectory: true)
    guard source.standardizedFileURL != destination.standardizedFileURL,
          fileManager.fileExists(atPath: source.path),
          !fileManager.fileExists(atPath: destination.path) else {
        return
    }

    // Stage on the destination volume so the final rename exposes the entire root at once.
    let staging = sharedContainer.appendingPathComponent(".ayugram-import-" + UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: staging) }
    try fileManager.copyItem(at: source, to: staging)
    try fileManager.moveItem(at: staging, to: destination)
}
