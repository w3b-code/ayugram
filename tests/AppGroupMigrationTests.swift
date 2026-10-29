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
        try fm.createDirectory(at: shared, withIntermediateDirectories: true)
        let fixtures = [".tempkey": "key-and-salt", "accounts-metadata/db": "account-records", "accounts-metadata/db-wal": "pending-transactions"]
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
