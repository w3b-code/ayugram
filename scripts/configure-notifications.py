#!/usr/bin/env python3
"""Keep an authenticated payload fallback and record content-free notification diagnostics."""
from pathlib import Path
import argparse


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError('Notification source changed near: ' + old[:95])
    return source.replace(old, new)


def configure(root: Path):
    service = root / 'Telegram/NotificationService/Sources/NotificationService.swift'
    source = service.read_text()
    source = replace_once(source, '            var recordId: AccountRecordId?\n', '            var recordId: AccountRecordId?\n            var backupNotificationKey: MasterNotificationKey?\n')
    source = replace_once(source, '                                    recordId = listRecord.id\n', '''                                    recordId = listRecord.id
                                    if let keyData = backupData.data?.notificationEncryptionKey {
                                        backupNotificationKey = MasterNotificationKey(id: notificationEncryptionKeyId, data: keyData)
                                    }
''')
    anchor = '            let _ = (standaloneStateManager(\n'
    fallback = '''            AyuNotificationDiagnostics.record(.keyMatched)
            var payloadFallback: NotificationContent?
            let decryptedBackupPayload: [String: Any]?
            if let backupNotificationKey,
               let data = decryptedNotificationPayload(key: backupNotificationKey, data: payloadData) {
                decryptedBackupPayload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            } else {
                decryptedBackupPayload = nil
            }
            if let json = decryptedBackupPayload, AyuNotificationDiagnostics.isServicePayload(json) {
                // Publish a non-alerting result before any account database/network wait.
                // Continue through the normal actions to update badges and remove read pushes.
                let serviceContent = NotificationContent(isLockedMessage: nil)
                payloadFallback = serviceContent
                updateCurrentContent(serviceContent)
                AyuNotificationDiagnostics.record(.servicePush, hasBody: false)
            }
            if let json = decryptedBackupPayload,
               let alert = AyuNotificationDiagnostics.alert(from: json) {
                var fallback = NotificationContent(isLockedMessage: isLockedMessage)
                fallback.title = alert.title
                fallback.subtitle = alert.subtitle
                fallback.body = alert.body
                if let value = json["silent"] as? String, let silent = Int(value) {
                    fallback.silent = silent != 0
                }
                fallback.userInfo["accountId"] = "\\(recordId.int64)"
                for name in ["from_id", "chat_id", "channel_id", "msg_id"] {
                    if let value = json[name] { fallback.userInfo[name] = value }
                }
                if let aps = json["aps"] as? [String: Any] {
                    fallback.sound = aps["sound"] as? String
                    fallback.threadId = aps["thread-id"] as? String
                    fallback.category = aps["category"] as? String
                    if let category = fallback.category, ["r", "m"].contains(category), json["chat_id"] != nil || json["channel_id"] != nil {
                        fallback.category = "g" + category
                    }
                }
                payloadFallback = fallback
                updateCurrentContent(fallback)
                AyuNotificationDiagnostics.record(.decrypted, hasBody: true, privacyHidden: isLockedMessage != nil)
                queue.after(3.0, { [weak self] in
                    guard let strongSelf = self else { return }
                    AyuNotificationDiagnostics.record(.payloadFallback)
                    if let stateManager = strongSelf.stateManager,
                       let value = json["msg_id"] as? String, let id = Int32(value) {
                        let peerId: PeerId?
                        if let value = json["from_id"] as? String, let id = Int64(value) {
                            peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))
                        } else if let value = json["chat_id"] as? String, let id = Int64(value) {
                            peerId = PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(id))
                        } else if let value = json["channel_id"] as? String, let id = Int64(value) {
                            peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(id))
                        } else { peerId = nil }
                        if let peerId {
                            let _ = stateManager.postbox.transaction { transaction -> Void in
                                _internal_setMessageNotificationWasDisplayed(transaction: transaction, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: id))
                            }.start()
                        }
                    }
                    completed()
                })
            }

'''
    source = replace_once(source, anchor, fallback+anchor)
    start = source.index('            var payloadFallback: NotificationContent?')
    end = source.index('                    Logger.shared.log("NotificationService \\(episode)", "Decrypted payload:')
    before, handling, after = source[:start], source[start:end], source[end:]
    handling = handling.replace('let content = NotificationContent(isLockedMessage: nil)', 'let content = payloadFallback ?? NotificationContent(isLockedMessage: nil)')
    handling = handling.replace('guard let notificationsKey = notificationsKey else {', 'guard let notificationsKey = notificationsKey ?? backupNotificationKey else {')
    source = before+handling+after
    payload_log = '                    Logger.shared.log("NotificationService \\(episode)", "Decrypted payload: \\(payloadJson)")'
    source = replace_once(source, payload_log, '''                    if AyuNotificationDiagnostics.isServicePayload(payloadJson) {
                        updateCurrentContent(NotificationContent(isLockedMessage: nil))
                        AyuNotificationDiagnostics.record(.servicePush, hasBody: false)
                    }

''' + payload_log)
    # As in Swiftgram's legacyNotificationsFix, an empty result must not restore
    # the original generic APNs text on iOS. This also covers already-read messages.
    content_end = '        return content\n    }\n}\n\nprivate func getCurrentRenderedTotalUnreadCount'
    source = replace_once(source, content_end, '        AyuNotificationDiagnostics.suppressEmptyNotification(content)\n' + content_end)
    for message, phase in [
        ("Couldn't find a matching decryption key", 'keyNotFound'),
        ("Didn't receive stateManager", 'databaseUnavailable'),
        ("Didn't receive decryption key", 'keyUnavailable'),
        ("Couldn't decrypt payload", 'decryptionFailed'),
    ]:
        old = 'Logger.shared.log("NotificationService \\(episode)", "'+message+'")'
        position = source.index(old)
        indent = source[source.rfind('\n', 0, position)+1:position]
        source = replace_once(source, old, 'AyuNotificationDiagnostics.record(.'+phase+')\n'+indent+old)
    source = replace_once(source, '                            Logger.shared.log("NotificationService \\(episode)", "Will poll")', '                            AyuNotificationDiagnostics.record(.waitingForNetwork)\n                            Logger.shared.log("NotificationService \\(episode)", "Will poll")')
    source = replace_once(source, '                                            let _ = connectionGaveUp.swap(true)', '                                            AyuNotificationDiagnostics.record(.networkTimeout)\n                                            let _ = connectionGaveUp.swap(true)')
    source = replace_once(source, '                                        return (content, nil)\n                                    }\n                                    |> then(', '''                                        if let messageId, _internal_getMessageNotificationWasDisplayed(transaction: transaction, id: messageId) {
                                            content = NotificationContent(isLockedMessage: nil)
                                        }
                                        updateCurrentContent(content)
                                        return (content, nil)
                                    }
                                    |> then(''')
    source = replace_once(source, '        self.initialContent = request.content', '        AyuNotificationDiagnostics.record(.received)\n        let _ = self.content.swap(nil)\n        self.initialContent = request.content')
    source = replace_once(source, '            return BoxedNotificationServiceHandler(value: NotificationServiceHandler(', '            let handler = NotificationServiceHandler(')
    source = replace_once(source, '                payload: request.content.userInfo\n            ))', '''                payload: request.content.userInfo
            )
            if handler == nil, let strongSelf = self, let callback = strongSelf.contentHandler {
                AyuNotificationDiagnostics.record(.initializationFailed)
                strongSelf.contentHandler = nil
                callback(request.content)
            }
            return BoxedNotificationServiceHandler(value: handler)''')
    source = replace_once(source, '                            contentHandler(content.generate())', '''                            let rendered = content.generate()
                            AyuNotificationDiagnostics.record(.delivered, hasBody: !rendered.body.isEmpty)
                            contentHandler(rendered)''')
    source = replace_once(source, '                            contentHandler(initialContent)', '                            AyuNotificationDiagnostics.record(.delivered, hasBody: !initialContent.body.isEmpty)\n                            contentHandler(initialContent)')
    source = replace_once(source, '    override func serviceExtensionTimeWillExpire() {', '    override func serviceExtensionTimeWillExpire() {\n        AyuNotificationDiagnostics.record(.expired)')

    settings = root / 'submodules/SettingsUI/Sources/AyuGram/AyuGramSettingsController.swift'
    screen = settings.read_text()
    screen = replace_once(screen, '    let testAIModels: () -> Void', '    let testAIModels: () -> Void\n    let notificationDiagnostics: () -> Void')
    screen = replace_once(screen, 'testAIModels: @escaping () -> Void) {', 'testAIModels: @escaping () -> Void, notificationDiagnostics: @escaping () -> Void) {')
    screen = replace_once(screen, '        self.testAIModels = testAIModels', '        self.testAIModels = testAIModels\n        self.notificationDiagnostics = notificationDiagnostics')
    screen = replace_once(screen, '    case peerId\n}', '    case peerId\n    case notifications\n}')
    screen = replace_once(screen, '    case testAIModels(id: Int32, section: AyuGramSettingsSection)', '    case testAIModels(id: Int32, section: AyuGramSettingsSection)\n    case notificationDiagnostics(id: Int32, section: AyuGramSettingsSection)')
    screen = screen.replace('let .testAIModels(_, section):', 'let .testAIModels(_, section), let .notificationDiagnostics(_, section):')
    screen = screen.replace('let .testAIModels(id, _):', 'let .testAIModels(id, _), let .notificationDiagnostics(id, _):')
    screen = replace_once(screen, '        case .testAIModels:\n', '''        case .notificationDiagnostics:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Проверка уведомлений", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.notificationDiagnostics()
            })
        case .testAIModels:
''')
    screen = replace_once(screen, '    return entries\n}', '    header(.notifications, "УВЕДОМЛЕНИЯ")\n    add { .notificationDiagnostics(id: $0, section: .notifications) }\n    footer(.notifications, "Проверяет доступ к общей папке и последний этап обработки push. Текст сообщений и ключи в проверку не записываются.")\n\n    return entries\n}')
    screen = replace_once(screen, '    var windowImpl: (() -> UIWindow?)?', '    var windowImpl: (() -> UIWindow?)?\n    var presentControllerImpl: ((ViewController) -> Void)?')
    screen = replace_once(screen, '        ayuAIPresentSpeedTest(context: context, window: windowImpl?())\n    })', '''        ayuAIPresentSpeedTest(context: context, window: windowImpl?())
    }, notificationDiagnostics: {
        presentControllerImpl?(textAlertController(context: context, title: "Проверка уведомлений", text: AyuNotificationDiagnostics.report(), actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]))
    })''')
    screen = replace_once(screen, '    windowImpl = { [weak controller] in', '    presentControllerImpl = { [weak controller] c in\n        controller?.present(c, in: .window(.root))\n    }\n    windowImpl = { [weak controller] in')

    helper = Path(__file__).resolve().parents[1] / 'runtime/AyuNotificationDiagnostics.swift'
    helper_source = helper.read_text()
    updates = {
        service: source,
        settings: screen,
        root / 'Telegram/NotificationService/Sources/AyuNotificationDiagnostics.swift': helper_source,
        root / 'submodules/AyuGram/AyuGramSettings/Sources/AyuNotificationDiagnostics.swift': helper_source,
        root / 'submodules/AyuGram/AyuGramSettings/Sources/AyuAppGroupResolver.swift': (helper.parent / 'AyuAppGroupResolver.swift').read_text(),
        root / 'submodules/TelegramCore/Sources/AyuGram/AyuHistoryRetention.swift': (helper.parent / 'AyuHistoryRetention.swift').read_text(),
    }
    for path, text in updates.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('telegram', type=Path)
    configure(parser.parse_args().telegram)
    print('Configured authenticated notification fallback and diagnostics')
