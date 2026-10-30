import Foundation

@main
struct AppGroupResolverTests {
    static func main() throws {
        typealias Resolver = AyuAppGroupResolver
        let five = "group.example.5", three = "group.example.3", one = "group.example.1"
        func choose(_ main: [String]?, _ service: [String]?, accessible: [String]) -> String? {
            Resolver.choose(configured: five, fallback: "group.ph.telegra.Telegraph", mainGroups: main, serviceGroups: service, canAccess: accessible.contains)
        }
        // Build 109's configured .5 is inaccessible after re-signing. Use an actually
        // permitted shared group, not the first entry in the certificate UI.
        precondition(choose([one, three], [three], accessible: [one, three]) == three)
        precondition(choose([five, three], [three, five], accessible: [three, five]) == five)
        precondition(choose([one, three], [three, one], accessible: [one, three]) == one)
        precondition(choose([one], [three], accessible: [one]) == nil)
        precondition(choose([], [], accessible: []) == nil)
        precondition(choose([five], [five], accessible: []) == nil)
        precondition(choose(nil, nil, accessible: [five]) == five)

        func words(_ values: [Int], little: Bool = false) -> Data {
            var data = Data()
            for value in values {
                for byte in (little ? [0, 8, 16, 24] : [24, 16, 8, 0]) { data.append(UInt8((value >> byte) & 255)) }
            }
            return data
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["com.apple.security.application-groups": [three]], format: .xml, options: 0)
        let entitlement = words([0xfade7171, plist.count + 8]) + plist
        let signature = words([0xfade0cc0, entitlement.count + 20, 1, 5, 20]) + entitlement
        let header = words([0xfeedfacf, 0x0100000c, 0, 2, 1, 16, 0, 0], little: true)
        let commands = words([0x1d, 16, 48, signature.count], little: true)
        let executable = header + commands + signature
        precondition(Resolver.signedGroups(in: executable) == [three])
        let fat = words([0xcafebabe, 1, 0x0100000c, 0, 28, executable.count, 0]) + executable
        precondition(Resolver.signedGroups(in: fat) == [three])
        for size in [0, 4, 31, 47, 60, executable.count - 1] {
            precondition(Resolver.signedGroups(in: executable.prefix(size)) == nil)
        }
        var malformed = executable
        malformed.replaceSubrange(40..<44, with: words([0x7fffffff], little: true))
        precondition(Resolver.signedGroups(in: malformed) == nil)
        print("Signed App Group resolver checks passed")
    }
}
