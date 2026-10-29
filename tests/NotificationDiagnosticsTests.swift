import Foundation

@main
struct NotificationDiagnosticsTests {
    static func main() throws {
        typealias Diagnostics = AyuNotificationDiagnostics
        let group = "group.example.ayugram.5"
        precondition(Diagnostics.groupIdentifier(bundleIdentifier: "ph.telegra.Telegraph", isExtension: false, override: group) == group)
        precondition(Diagnostics.groupIdentifier(bundleIdentifier: "ph.telegra.Telegraph.NotificationService", isExtension: true, override: group) == group)
        precondition(Diagnostics.groupIdentifier(bundleIdentifier: "ph.telegra.Telegraph.NotificationService", isExtension: true, override: nil) == "group.ph.telegra.Telegraph")

        let alert = Diagnostics.alert(from: ["aps": ["alert": ["title": "Sender", "body": "Private message"]]])
        precondition(alert?.title == "Sender" && alert?.body == "Private message")
        precondition(Diagnostics.alert(from: ["aps": ["alert": "A message"]])?.body == "A message")
        precondition(Diagnostics.alert(from: ["aps": ["alert": ["title": "Title only"]]]) == nil)
        precondition(Diagnostics.alert(from: ["loc-key": "MESSAGE_DELETED", "aps": ["alert": "control"]]) == nil)
        precondition(Diagnostics.alert(from: ["story_id": "1", "aps": ["alert": "story"]]) == nil)
        precondition(Diagnostics.alert(from: ["call_id": "1", "aps": ["alert": "call"]]) == nil)
        precondition(Diagnostics.alert(from: ["encryption_id": "1", "aps": ["alert": "secret chat"]]) == nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("status.json")
        Diagnostics.write(.received, to: file)
        Diagnostics.write(.decryptionFailed, to: file)
        Diagnostics.write(.delivered, to: file, hasBody: true)
        var record = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(record["failure"] as? String == "decryptionFailed")
        precondition(record["phase"] as? String == "delivered")
        precondition(Set(record.keys).isSubset(of: ["phase", "failure", "timestamp", "usedPayloadFallback", "messageBodyPresent", "privacyHidden"]))
        let statusText = String(data: try Data(contentsOf: file), encoding: .utf8)!
        precondition(!statusText.contains("Private message"))

        Diagnostics.write(.received, to: file)
        Diagnostics.write(.decrypted, to: file, hasBody: true, privacyHidden: true)
        Diagnostics.write(.payloadFallback, to: file)
        Diagnostics.write(.delivered, to: file)
        record = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(record["failure"] == nil)
        precondition(record["usedPayloadFallback"] as? Bool == true)
        precondition(record["privacyHidden"] as? Bool == true)
        print("Notification payload and diagnostics checks passed")
    }
}
