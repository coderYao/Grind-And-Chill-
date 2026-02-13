import Foundation

struct HistoryImportUndoStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = AppStorageKeys.lastImportUndoPayload
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> HistoryImportService.UndoPayload? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HistoryImportService.UndoPayload.self, from: data)
    }

    func save(_ payload: HistoryImportService.UndoPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: key)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }
}
