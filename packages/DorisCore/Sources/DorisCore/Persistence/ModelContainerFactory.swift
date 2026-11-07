import Foundation
import DorisIPC
import SwiftData

public enum ModelContainerFactory {
    public enum FactoryError: Error {
        case appGroupUnavailable
    }

    /// Creates the shared Doris `ModelContainer`.
    ///
    /// Both iOS and macOS call this via `DorisRuntime.shared.container`
    /// so they always use the **same** schema and CloudKit container —
    /// the single source of truth for cross-device data consistency.
    ///
    /// Migration: SwiftData performs automatic lightweight migration for
    /// additive changes (new optional columns, new relationships). An
    /// explicit `SchemaMigrationPlan` is not needed here because adding
    /// `Note.dueDate: Date?` is a nullable column addition — existing
    /// rows silently get NULL. For non-lightweight migrations (renaming
    /// columns, dropping non-null columns) a versioned migration plan
    /// would be required.
    /// Every synced model. The CloudKit schema initializer pushes this same
    /// list, so a model added here reaches CloudKit's schema too.
    public static let models: [any PersistentModel.Type] = [
        Folder.self, Note.self, ChecklistItem.self,
        Tag.self, Attachment.self, Message.self,
        Device.self, UserSettings.self,
        ActivityDay.self
    ]

    public static func make(useCloudKit: Bool = true, inMemory: Bool = false) throws -> ModelContainer {
        let url = try storeURL(inMemory: inMemory)
        let schema = Schema(models)

        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(
                "Doris-InMemory",
                schema: schema,
                isStoredInMemoryOnly: true
            )
        } else if useCloudKit {
            config = ModelConfiguration(
                "Doris",
                schema: schema,
                url: url,
                cloudKitDatabase: .private(DorisIdentifiers.cloudKitContainer)
            )
        } else {
            config = ModelConfiguration(
                "Doris",
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        }

        return try ModelContainer(for: schema, configurations: [config])
    }

    public static func storeURL(inMemory: Bool) throws -> URL {
        if inMemory {
            return URL(fileURLWithPath: "/dev/null")
        }
        // Single source of truth: IPCDirectory.containerURL() honors DORIS_IPC_ROOT
        // for dev builds and falls back through the App Group container otherwise.
        let group = try IPCDirectory.containerURL()
        let storeDir = group.appendingPathComponent("Store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        return storeDir.appendingPathComponent("Doris.sqlite")
    }
}
