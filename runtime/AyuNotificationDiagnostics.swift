import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

public enum AyuNotificationDiagnostics {
    public enum Phase: String, Codable {
        case received, keyMatched, keyNotFound, databaseUnavailable, keyUnavailable
        case decryptionFailed, decrypted, waitingForNetwork, networkTimeout
        case payloadFallback, delivered, initializationFailed, expired, servicePush, targetedFetch

        var failure: Bool {
            switch self {
            case .keyNotFound, .databaseUnavailable, .keyUnavailable, .decryptionFailed, .networkTimeout, .initializationFailed, .expired:
                return true
            default:
                return false
            }
        }

        var description: String {
            switch self {
            case .received: return "Расширение получило push"
            case .keyMatched: return "Аккаунт и ключ push найдены"
            case .keyNotFound: return "Не найден аккаунт с подходящим ключом push"
            case .databaseUnavailable: return "Расширение не смогло открыть базу аккаунта"
            case .keyUnavailable: return "Ключ расшифровки недоступен"
            case .decryptionFailed: return "Не удалось расшифровать push"
            case .decrypted: return "Push расшифрован"
            case .waitingForNetwork: return "Ожидание синхронизации с Telegram"
            case .networkTimeout: return "Синхронизация не завершилась вовремя"
            case .payloadFallback: return "Показан текст push без ожидания синхронизации"
            case .delivered: return "Уведомление передано iOS"
            case .initializationFailed: return "Не удалось запустить обработчик push"
            case .expired: return "iOS завершила обработчик по тайм-ауту"
            case .servicePush: return "Служебный push обработан без нового сообщения"
            case .targetedFetch: return "Загрузка сообщения из push без полной синхронизации"
            }
        }
    }

    private struct State: Codable {
        var phase: Phase
        var failure: Phase?
        var timestamp: TimeInterval
        var usedPayloadFallback: Bool
        var messageBodyPresent: Bool?
        var privacyHidden: Bool?
        var servicePush: Bool?
        var processingSeconds: TimeInterval?
    }
    private static let lock = NSLock()

    static func groupIdentifier(bundleIdentifier: String, isExtension: Bool, override: String?) -> String {
        if let override, !override.isEmpty { return override }
        let base = isExtension ? String(bundleIdentifier.split(separator: ".").dropLast().joined(separator: ".")) : bundleIdentifier
        return "group." + base
    }

    private static var groupIdentifier: String {
        let fallback = groupIdentifier(bundleIdentifier: Bundle.main.bundleIdentifier ?? "ph.telegra.Telegraph", isExtension: Bundle.main.bundlePath.hasSuffix(".appex"), override: nil)
        return AyuAppGroupResolver.groupIdentifier(configured: Bundle.main.object(forInfoDictionaryKey: "AyuGramAppGroup") as? String, fallback: fallback)
    }

    private static var container: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    static func write(_ phase: Phase, to url: URL, hasBody: Bool? = nil, privacyHidden: Bool? = nil, processingSeconds: TimeInterval? = nil, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var state = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
            ?? State(phase: phase, failure: nil, timestamp: 0, usedPayloadFallback: false, messageBodyPresent: nil, privacyHidden: nil)
        if phase == .received {
            state.failure = nil
            state.usedPayloadFallback = false
            state.messageBodyPresent = nil
            state.privacyHidden = nil
            state.servicePush = nil
            state.processingSeconds = nil
        }
        if phase == .servicePush { state.servicePush = true }
        if phase == .payloadFallback { state.usedPayloadFallback = true }
        if let hasBody { state.messageBodyPresent = hasBody }
        if let privacyHidden { state.privacyHidden = privacyHidden }
        if let processingSeconds { state.processingSeconds = max(0, processingSeconds) }
        state.phase = phase
        state.timestamp = timestamp
        if phase.failure { state.failure = phase }
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: url, options: .atomic) }
    }

    public static func record(_ phase: Phase, hasBody: Bool? = nil, privacyHidden: Bool? = nil, processingSeconds: TimeInterval? = nil) {
        guard let container else { return }
        write(phase, to: container.appendingPathComponent("ayu-notification-status.json"), hasBody: hasBody, privacyHidden: privacyHidden, processingSeconds: processingSeconds)
    }

    public static func report() -> String {
        let fm = FileManager.default
        var lines = ["Сборка: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")", "App Group: \(groupIdentifier)"]
        if let configured = Bundle.main.object(forInfoDictionaryKey: "AyuGramAppGroup") as? String, configured != groupIdentifier {
            lines.append("Группа в сборке: " + configured)
        }
        for (name, groups) in [("приложения", AyuAppGroupResolver.mainGroups), ("расширения", AyuAppGroupResolver.serviceGroups)] {
            if let groups {
                lines.append("App Groups в подписи " + name + ": " + (groups.isEmpty ? "отсутствуют" : groups.joined(separator: ", ")))
            } else {
                lines.append("App Groups в подписи " + name + ": не удалось прочитать")
            }
        }
        let plugins = Bundle.main.builtInPlugInsURL.flatMap { try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? []
        let service = plugins.compactMap { Bundle(url: $0) }.first { bundle in
            return (bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"] as? String == "com.apple.usernotifications.service"
        }
        lines.append(service == nil ? "Расширение уведомлений: отсутствует после подписи" : "Расширение уведомлений: установлено")
        guard let container else {
            return (lines + ["Общая папка недоступна. Профиль и подпись приложения и NotificationService должны разрешать одну общую App Group. Одной переменной GitHub для выдачи этих прав недостаточно."]).joined(separator: "\n")
        }
        let probe = container.appendingPathComponent(".ayu-probe-" + UUID().uuidString)
        do {
            try Data().write(to: probe)
            try fm.removeItem(at: probe)
            lines.append("Общая папка: чтение и запись доступны")
        } catch { lines.append("Общая папка: запись недоступна") }
        if let service, service.object(forInfoDictionaryKey: "AyuGramAppGroup") as? String != Bundle.main.object(forInfoDictionaryKey: "AyuGramAppGroup") as? String {
            lines.append("Группы приложения и расширения не совпадают")
        }
        let path = container.appendingPathComponent("ayu-notification-status.json")
        if let data = try? Data(contentsOf: path), let state = try? JSONDecoder().decode(State.self, from: data) {
            lines.append("Последний этап: " + state.phase.description)
            lines.append("Время: " + DateFormatter.localizedString(from: Date(timeIntervalSince1970: state.timestamp), dateStyle: .short, timeStyle: .medium))
            if let seconds = state.processingSeconds {
                lines.append(String(format: "Обработка push: %.2f с", seconds))
            }
            if let failure = state.failure { lines.append("Последняя ошибка: " + failure.description) }
            if state.usedPayloadFallback { lines.append("Использован резервный текст из push") }
            if state.servicePush == true { lines.append("Тип push: служебная синхронизация") }
            if let hasBody = state.messageBodyPresent { lines.append("Поле текста: " + (hasBody ? "есть" : "нет")) }
            if let hidden = state.privacyHidden { lines.append("Скрыто блокировкой приложения: " + (hidden ? "да" : "нет")) }
        } else {
            lines.append("Запуск расширения не зафиксирован. Дождитесь нового push и снова откройте проверку.")
        }
        lines.append("Проверка не записывает сообщения, имена, токены и ключи.")
        return lines.joined(separator: "\n")
    }

    /// Only inspect the authenticated, decrypted payload. The outer APNs alert can be generic.
    static func isServicePayload(_ payload: [String: Any]) -> Bool {
        guard let key = payload["loc-key"] as? String else { return false }
        return ["READ_HISTORY", "READ_REACTION", "READ_STORIES", "MESSAGE_DELETED", "MESSAGE_MUTED", "SESSION_REVOKE"].contains(key)
    }

#if canImport(UserNotifications)
    /// Empty service results need explicit passive content on iOS versions that otherwise
    /// restore the original generic APNs alert. Keep the badge and message content intact.
    static func suppressEmptyNotification(_ content: UNMutableNotificationContent) {
        guard content.title.isEmpty, content.subtitle.isEmpty, content.body.isEmpty,
              content.attachments.isEmpty else { return }
        content.title = " "
        content.sound = nil
        content.categoryIdentifier = ""
        content.threadIdentifier = "ayu-service-notifications"
        if #available(iOS 15.0, macOS 12.0, *) {
            content.interruptionLevel = .passive
            content.relevanceScore = 0.0
        }
    }
#endif

    static func canFetchMessageDirectly(_ payload: [String: Any]) -> Bool {
        guard alert(from: payload) != nil, payload["attachb64"] == nil,
              payload["r"] == nil, payload["react_emoji"] == nil,
              let id = payload["msg_id"] as? String, let messageId = Int32(id), messageId > 0,
              ["from_id", "chat_id", "channel_id"].contains(where: { key in
                  (payload[key] as? String).flatMap(Int64.init) != nil
              }), let aps = payload["aps"] as? [String: Any],
              aps["r"] == nil, aps["react_emoji"] == nil,
              !["t", "st", "str"].contains(aps["category"] as? String ?? "") else { return false }
        return true
    }

    static func alert(from payload: [String: Any]) -> (title: String?, subtitle: String?, body: String)? {
        guard payload["loc-key"] == nil, payload["story_id"] == nil, payload["call_id"] == nil, payload["encryption_id"] == nil,
              let aps = payload["aps"] as? [String: Any] else { return nil }
        if let alert = aps["alert"] as? [String: Any], let body = alert["body"] as? String, !body.isEmpty {
            return (alert["title"] as? String, alert["subtitle"] as? String, body)
        }
        if let body = aps["alert"] as? String, !body.isEmpty { return (nil, nil, body) }
        return nil
    }
}
