import Foundation

/// Inspect our own installed signatures, never the certificate's private key.
enum AyuAppGroupResolver {
    static func signedGroups(in data: Data) -> [String]? {
        func number(_ offset: Int, _ little: Bool = false) -> Int? {
            guard offset >= 0, offset <= data.count - 4 else { return nil }
            let bytes = (0..<4).map { Int(data[offset + $0]) }
            return little ? bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24
                : bytes[3] | bytes[2] << 8 | bytes[1] << 16 | bytes[0] << 24
        }
        func thin(_ base: Int, _ size: Int) -> [String]? {
            guard size >= 32, base >= 0, base <= data.count - size,
                  let magic = number(base, true), magic == 0xfeedfacf || magic == 0xfeedface,
                  let count = number(base + 16, true), count <= 4096,
                  let commandSize = number(base + 20, true) else { return nil }
            let header = magic == 0xfeedfacf ? 32 : 28
            guard commandSize <= size - header else { return nil }
            let end = base + header + commandSize
            var command = base + header
            for _ in 0..<count {
                guard command <= end - 8, let type = number(command, true),
                      let length = number(command + 4, true), length >= 8, length <= end - command else { return nil }
                defer { command += length }
                if type != 0x1d { continue } // LC_CODE_SIGNATURE
                guard length >= 16, let offset = number(command + 8, true),
                      let signatureSize = number(command + 12, true), signatureSize >= 12,
                      offset <= size, signatureSize <= size - offset else { return nil }
                let start = base + offset
                guard number(start) == 0xfade0cc0, let blobSize = number(start + 4),
                      blobSize >= 12, blobSize <= signatureSize, let slots = number(start + 8),
                      slots <= (blobSize - 12) / 8 else { return nil }
                for slot in 0..<slots {
                    let index = start + 12 + slot * 8
                    guard let kind = number(index), let relative = number(index + 4) else { return nil }
                    if kind != 5 { continue } // CSSLOT_ENTITLEMENTS
                    guard relative <= blobSize - 8 else { return nil }
                    let blob = start + relative
                    guard number(blob) == 0xfade7171, let length = number(blob + 4),
                          length >= 8, length <= blobSize - relative,
                          let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: blob + 8 ..< blob + length), format: nil) as? [String: Any] else { return nil }
                    return (plist["com.apple.security.application-groups"] as? [String] ?? []).filter { $0.hasPrefix("group.") && !$0.contains("*") }.sorted()
                }
                return nil // DER-only or unavailable entitlement data: do not invent rights.
            }
            return nil
        }
        if number(0) == 0xcafebabe, let count = number(4), count <= 64, count <= (data.count - 8) / 20 {
            // Prefer arm64 in a universal executable.
            let slices = (0..<count).sorted { number(8 + $0 * 20) == 0x0100000c && number(8 + $1 * 20) != 0x0100000c }
            for slice in slices {
                guard let offset = number(8 + slice * 20 + 8), let size = number(8 + slice * 20 + 12) else { continue }
                if let groups = thin(offset, size) { return groups }
            }
            return nil
        }
        return thin(0, data.count)
    }

    static func choose(configured: String?, fallback: String, mainGroups: [String]?, serviceGroups: [String]?, canAccess: (String) -> Bool) -> String? {
        let common: Set<String>?
        if let mainGroups, let serviceGroups {
            common = Set(mainGroups).intersection(serviceGroups)
        } else if let known = mainGroups ?? serviceGroups {
            common = Set(known)
        } else {
            common = nil
        }
        let requested = [configured, fallback].compactMap { $0 }.filter { !$0.isEmpty }
        let candidates = requested + (common?.sorted() ?? [])
        var seen = Set<String>()
        return candidates.first { group in
            guard seen.insert(group).inserted, common?.contains(group) != false else { return false }
            return canAccess(group)
        }
    }

    private static func groups(_ bundle: Bundle?) -> [String]? {
        // Never copy the application's large executable into the extension's small memory budget.
        guard let url = bundle?.executableURL, let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return signedGroups(in: data)
    }

    private static let bundles: (Bundle, Bundle?) = {
        var url = Bundle.main.bundleURL
        while url.pathExtension != "app", url.path != "/" { url.deleteLastPathComponent() }
        let app = Bundle(url: url) ?? Bundle.main
        let plugins = app.builtInPlugInsURL.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? []
        let service = plugins.compactMap { Bundle(url: $0) }.first {
            ($0.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"] as? String == "com.apple.usernotifications.service"
        }
        return (app, service)
    }()
    static let mainGroups = groups(bundles.0)
    static let serviceGroups = groups(bundles.1)

    static func groupIdentifier(configured: String?, fallback: String) -> String {
        return choose(configured: configured, fallback: fallback, mainGroups: mainGroups, serviceGroups: serviceGroups, canAccess: {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }) ?? configured ?? fallback
    }
}
