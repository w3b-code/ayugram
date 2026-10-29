import Foundation

@main
struct AppGroupMigrationTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let legacy = root.appendingPathComponent("private")
        let shared = root.appendingPathComponent("shared")
        let data = legacy.appendingPathComponent("telegram-data")
        try fm.createDirectory(at: data.appendingPathComponent("accounts-metadata"), withIntermediateDirectories: true)
        try fm.createDirectory(at: data.appendingPathComponent("account-123/postbox"), withIntermediateDirectories: true)
        try fm.createDirectory(at: shared, withIntermediateDirectories: true)
        let fixtures = [".tempkey": "key-and-salt", "accounts-metadata/db": "account-records", "accounts-metadata/db-wal": "pending-transactions", "account-123/postbox/db": "real-messages"]
        for (path, value) in fixtures {
            try Data(value.utf8).write(to: data.appendingPathComponent(path))
        }

        try ayuMigrateLegacyAppGroupData(from: legacy, to: shared)
        for (path, value) in fixtures {
            let original = try Data(contentsOf: data.appendingPathComponent(path))
            let copied = try Data(contentsOf: shared.appendingPathComponent("telegram-data/" + path))
            precondition(original == Data(value.utf8) && copied == original, "Data or encryption key was lost")
        }
        let contents = try fm.contentsOfDirectory(atPath: shared.path)
        precondition(contents.allSatisfy { !$0.hasPrefix(".ayugram-import-") })

        // Running again cannot overwrite an existing shared account with the stale private copy.
        let sharedKey = shared.appendingPathComponent("telegram-data/.tempkey")
        try Data("new-shared-key".utf8).write(to: sharedKey)
        try ayuMigrateLegacyAppGroupData(from: legacy, to: shared)
        let retainedKey = try Data(contentsOf: sharedKey)
        precondition(retainedKey == Data("new-shared-key".utf8))
        try ayuMigrateLegacyAppGroupData(from: root.appendingPathComponent("missing-source"), to: shared)
        try ayuMigrateLegacyAppGroupData(from: legacy, to: legacy)

        // A push can initialize the new group before the app imports its account.
        let bootstrapContainer = root.appendingPathComponent("bootstrap")
        let bootstrap = bootstrapContainer.appendingPathComponent("telegram-data")
        try fm.createDirectory(at: bootstrap.appendingPathComponent("accounts-metadata"), withIntermediateDirectories: true)
        try Data("empty-metadata".utf8).write(to: bootstrap.appendingPathComponent("accounts-metadata/db"))
        try Data("bootstrap-key".utf8).write(to: bootstrap.appendingPathComponent(".tempkey"))
        try ayuMigrateLegacyAppGroupData(from: legacy, to: bootstrapContainer)
        let importedKey = try Data(contentsOf: bootstrap.appendingPathComponent(".tempkey"))
        precondition(importedKey == Data("key-and-salt".utf8))
        let importedMessages = try Data(contentsOf: bootstrap.appendingPathComponent("account-123/postbox/db"))
        precondition(importedMessages == Data("real-messages".utf8))
        let backups = try fm.contentsOfDirectory(at: bootstrapContainer, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".ayugram-bootstrap-") }
        precondition(backups.count == 1)
        let backupKey = try Data(contentsOf: backups[0].appendingPathComponent(".tempkey"))
        precondition(backupKey == Data("bootstrap-key".utf8), "The bootstrap must remain recoverable")

        // Unrecognized shared data is never treated as an empty bootstrap.
        let protectedContainer = root.appendingPathComponent("protected")
        let protectedRoot = protectedContainer.appendingPathComponent("telegram-data")
        try fm.createDirectory(at: protectedRoot, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: protectedRoot.appendingPathComponent("unknown-database"))
        try ayuMigrateLegacyAppGroupData(from: legacy, to: protectedContainer)
        precondition(!fm.fileExists(atPath: protectedRoot.appendingPathComponent(".tempkey").path))

        // A failed copy leaves the old installation readable and exposes no partial database.
        let missingDestination = root.appendingPathComponent("missing-parent/shared")
        do {
            try ayuMigrateLegacyAppGroupData(from: legacy, to: missingDestination)
            preconditionFailure("Expected migration to fail")
        } catch {
            precondition(fm.fileExists(atPath: data.appendingPathComponent(".tempkey").path))
            precondition(!fm.fileExists(atPath: missingDestination.appendingPathComponent("telegram-data").path))
        }
        print("App Group migration checks passed")
    }
}
