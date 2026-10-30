import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

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

        // Reading on desktop must never turn the generic outer APNs alert into a new message.
        for peer in ["from_id", "chat_id", "channel_id"] {
            let readPush: [String: Any] = ["loc-key": "READ_HISTORY", peer: "42", "max_id": "10", "aps": ["alert": "You have a new message"]]
            precondition(Diagnostics.isServicePayload(readPush))
            precondition(Diagnostics.alert(from: readPush) == nil)
        }
        for key in ["READ_REACTION", "READ_STORIES", "MESSAGE_DELETED", "MESSAGE_MUTED", "SESSION_REVOKE"] {
            precondition(Diagnostics.isServicePayload(["loc-key": key]))
        }
        let ordinaryPushes: [[String: Any]] = [
            ["from_id": "42", "msg_id": "11", "aps": ["alert": "New message"]],
            ["channel_id": "42", "msg_id": "11", "aps": ["alert": ["title": "Channel", "body": "New post"]]],
            ["loc-key": "CONF_CALL_REQUEST", "call_id": "1"],
            ["loc-key": "CONF_VIDEOCALL_REQUEST", "call_id": "1"],
            ["loc-key": "UNKNOWN"]
        ]
        for payload in ordinaryPushes {
            precondition(!Diagnostics.isServicePayload(payload))
        }
        // The desktop no-delay option has different scheduling rules; on iOS the
        // fast path targets only normal message pushes and still stores their data.
        for peer in ["from_id", "chat_id", "channel_id"] {
            var push: [String: Any] = [peer: "42", "msg_id": "11", "aps": ["alert": ["title": "Sender", "body": "Message"]]]
            precondition(Diagnostics.canFetchMessageDirectly(push))
            for field in ["attachb64", "story_id", "call_id", "encryption_id", "r", "react_emoji", "loc-key"] {
                var special = push
                special[field] = "1"
                precondition(!Diagnostics.canFetchMessageDirectly(special))
            }
            for category in ["t", "st", "str"] {
                push["aps"] = ["category": category, "alert": "Reaction"]
                precondition(!Diagnostics.canFetchMessageDirectly(push))
            }
            push["aps"] = ["alert": "Message", "react_emoji": "👍"]
            precondition(!Diagnostics.canFetchMessageDirectly(push))
        }
        precondition(!Diagnostics.canFetchMessageDirectly(["msg_id": "11", "aps": ["alert": "No peer"]]))
        precondition(!Diagnostics.canFetchMessageDirectly(["from_id": "42", "msg_id": "invalid", "aps": ["alert": "Message"]]))

#if canImport(UserNotifications)
        let service = UNMutableNotificationContent()
        service.badge = 3
        service.sound = .default
        service.categoryIdentifier = "r"
        Diagnostics.suppressEmptyNotification(service)
        precondition(service.title == " " && service.body.isEmpty && service.sound == nil)
        precondition(service.badge == 3 && service.categoryIdentifier.isEmpty)
        if #available(iOS 15.0, macOS 12.0, *) {
            precondition(service.interruptionLevel == .passive && service.relevanceScore == 0)
        }
        // Sender names, hidden-preview text, calls, and actual new messages retain presentation.
        for texts in [("Sender", "", "Message"), ("", "", "You have a new message"), ("Caller", "", ""), ("", "Subtitle", "")] {
            let message = UNMutableNotificationContent()
            message.title = texts.0
            message.subtitle = texts.1
            message.body = texts.2
            message.sound = .default
            Diagnostics.suppressEmptyNotification(message)
            precondition(message.title == texts.0 && message.subtitle == texts.1 && message.body == texts.2)
            precondition(message.sound != nil)
        }
#endif

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
        precondition(Set(record.keys).isSubset(of: ["phase", "failure", "timestamp", "usedPayloadFallback", "messageBodyPresent", "privacyHidden", "servicePush", "processingSeconds"]))
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
        Diagnostics.write(.received, to: file)
        Diagnostics.write(.servicePush, to: file, hasBody: false)
        Diagnostics.write(.delivered, to: file, hasBody: false)
        record = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(record["servicePush"] as? Bool == true)
        precondition(record["messageBodyPresent"] as? Bool == false)
        Diagnostics.write(.received, to: file)
        record = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(record["servicePush"] == nil)
        Diagnostics.write(.received, to: file, timestamp: 100)
        Diagnostics.write(.targetedFetch, to: file, timestamp: 100.1)
        Diagnostics.write(.delivered, to: file, hasBody: true, processingSeconds: 0.2, timestamp: 100.2)
        record = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(record["processingSeconds"] as? Double == 0.2)
        precondition(record["timestamp"] as? Double == 100.2)
        Diagnostics.write(.received, to: file, timestamp: 200)
        record = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(record["processingSeconds"] == nil)
        print("Notification payload and diagnostics checks passed")
    }
}
