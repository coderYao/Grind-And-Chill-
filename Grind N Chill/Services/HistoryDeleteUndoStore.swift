import Foundation

struct HistoryDeleteUndoStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = AppStorageKeys.lastHistoryDeleteUndoPayload
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> HistoryViewModel.DeleteUndoPayload? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HistoryViewModel.DeleteUndoPayload.self, from: data)
    }

    func save(_ payload: HistoryViewModel.DeleteUndoPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: key)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }
}
