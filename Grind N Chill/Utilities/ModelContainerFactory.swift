import Foundation
import SwiftData

enum ModelContainerFactory {
    static func makeSharedContainer() -> ModelContainer {
        let cloudKitEnabled = shouldUseCloudKit()

        do {
#if DEBUG
            if shouldResetForUITests() {
                _ = removeDefaultStoreArtifacts()
            }
#endif
            return try makeContainer(cloudKitEnabled: cloudKitEnabled)
        } catch {
#if DEBUG
            if recoverFromIncompatibleStore() {
                do {
                    return try makeContainer(cloudKitEnabled: cloudKitEnabled)
                } catch {
                    fatalError("Failed to recreate SwiftData store after recovery: \(error)")
                }
            }
#endif
            if cloudKitEnabled {
                do {
                    print("CloudKit SwiftData container failed to load. Falling back to local-only store. Error: \(error)")
                    return try makeContainer(cloudKitEnabled: false)
                } catch {
                    fatalError("Failed to load SwiftData store with CloudKit and local fallback: \(error)")
                }
            }
            fatalError("Failed to load SwiftData store: \(error)")
        }
    }

    private static func makeContainer(cloudKitEnabled: Bool) throws -> ModelContainer {
        let schema = Schema([Category.self, Entry.self, BadgeAward.self])
        let configuration: ModelConfiguration

        if cloudKitEnabled {
            configuration = ModelConfiguration(cloudKitDatabase: .automatic)
        } else {
            configuration = ModelConfiguration()
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func shouldUseCloudKit() -> Bool {
#if DEBUG
        let processInfo = ProcessInfo.processInfo
        if processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return false
        }

        if processInfo.arguments.contains("-ui-testing-reset-store") ||
            processInfo.arguments.contains("-ui-testing-disable-cloudkit") {
            return false
        }
#endif
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil {
            return false
        }
        return true
    }

#if DEBUG
    private static func recoverFromIncompatibleStore() -> Bool {
        removeDefaultStoreArtifacts()
    }

    private static func shouldResetForUITests() -> Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-store")
    }

    private static func removeDefaultStoreArtifacts() -> Bool {
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
                print("Failed to remove store artifact at \(url): \(error)")
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
