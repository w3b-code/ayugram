import Foundation

@main
struct HistoryRetentionTests {
    struct SavedMessage: Equatable {
        let text: String
        let mediaPath: String
        let timestamp: Int32
    }

    static func main() {
        let original = SavedMessage(text: "Saved message", mediaPath: "photo-local", timestamp: 1000)
        var messages = [1: original, 2: SavedMessage(text: "New deletion", mediaPath: "video-local", timestamp: 2000)]
        var archived: Set<Int> = [1]
        var archiveCalls = 0
        var physicallyRemoved: [Int] = []

        let remoteDeletion: ([Int], Bool) -> Void = { ids, saving in
            AyuHistoryRetention.apply(ids: ids, savingEnabled: saving, isSaved: { archived.contains($0) }, save: { ids in
                archiveCalls += 1
                var absent: [Int] = []
                for id in ids {
                    if messages[id] != nil { archived.insert(id) } else { absent.append(id) }
                }
                return absent
            }, remove: { ids in
                physicallyRemoved.append(contentsOf: ids)
                for id in ids { messages.removeValue(forKey: id) }
            })
        }

        // Opening a saved message starts a server refresh that no longer contains it.
        remoteDeletion([1], true)
        remoteDeletion([1], true)
        precondition(messages[1] == original && archiveCalls == 0 && physicallyRemoved.isEmpty)

        // A late response must preserve an archive made while that request was in flight.
        archived.insert(2)
        let second = messages[2]
        remoteDeletion([1, 2, 3], true)
        precondition(messages[1] == original && messages[2] == second && physicallyRemoved == [3])

        // Turning off saving new deletions must not destroy an old saved message.
        messages[4] = original
        remoteDeletion([1, 4], false)
        precondition(messages[1] == original && messages[4] == nil && physicallyRemoved == [3, 4])

        // A deletion discovered by history validation is archived when saving is enabled.
        messages[5] = original
        remoteDeletion([5], true)
        precondition(archived.contains(5) && messages[5] == original)
        let callCount = archiveCalls
        remoteDeletion([5], false)
        precondition(messages[5] == original && archiveCalls == callCount)

        print("Deleted history retention checks passed")
    }
}
