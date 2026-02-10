import Foundation
import SwiftData

enum ModelContainerFactory {
    static func makeSharedContainer() -> ModelContainer {
        do {
            return try makeContainer()
        } catch {
#if DEBUG
            if recoverFromIncompatibleStore() {
                do {
                    return try makeContainer()
                } catch {
                    fatalError("Failed to recreate SwiftData store after recovery: \(error)")
                }
            }
#endif
            fatalError("Failed to load SwiftData store: \(error)")
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Category.self, Entry.self, BadgeAward.self])
        let configuration = ModelConfiguration()
        return try ModelContainer(for: schema, configurations: [configuration])
    }

#if DEBUG
    private static func recoverFromIncompatibleStore() -> Bool {
        guard let storeURL = defaultStoreURL() else { return false }

        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]

        var removedAny = false
        let fileManager = FileManager.default

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
                removedAny = true
            } catch {
                print("Failed to remove incompatible store artifact at \(url): \(error)")
            }
        }

        return removedAny
    }
#endif

    private static func defaultStoreURL() -> URL? {
        do {
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return appSupportURL.appendingPathComponent("default.store")
        } catch {
            print("Failed to locate Application Support directory: \(error)")
            return nil
        }
    }
}
