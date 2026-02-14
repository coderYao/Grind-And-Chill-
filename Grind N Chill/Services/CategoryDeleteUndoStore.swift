import Foundation

struct CategoryDeleteUndoStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = AppStorageKeys.lastCategoryDeleteUndoPayload
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> CategoriesViewModel.DeleteUndoPayload? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CategoriesViewModel.DeleteUndoPayload.self, from: data)
    }

    func save(_ payload: CategoriesViewModel.DeleteUndoPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: key)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }
}
