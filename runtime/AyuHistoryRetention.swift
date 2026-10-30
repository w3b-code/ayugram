/// Remote absence is expected for a locally saved deletion. Only the user's
/// explicit delete action should erase that copy; disabling saving affects new deletions.
enum AyuHistoryRetention {
    static func apply<Id>(ids: [Id], savingEnabled: Bool, isSaved: (Id) -> Bool, save: ([Id]) -> [Id], remove: ([Id]) -> Void) {
        let pending = ids.filter { !isSaved($0) }
        guard !pending.isEmpty else { return }
        let removable = savingEnabled ? save(pending) : pending
        if !removable.isEmpty {
            remove(removable)
        }
    }
}
