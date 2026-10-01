#if DEBUG
import Foundation
import CoreData
import Security
import SwiftData
import DorisCore
import DorisIPC

/// Pushes the full SwiftData schema — every record type and field,
/// including asset fields — to the CloudKit **Development** environment,
/// so it can then be deployed to Production from the CloudKit console.
///
/// Needed because every build is pinned to Production (see the
/// entitlements file), and Production never learns a new field by itself:
/// writes carrying one just fail, silently. Run it from a Debug build
/// signed with `icloud-container-environment = Development`:
///
///     Doris.app/Contents/MacOS/Doris --init-cloudkit-schema
///
/// It uses a throwaway store and exits before the app starts, so it can
/// run beside the installed Doris. Apple's recipe for SwiftData:
/// "Syncing model data across a person's devices".
enum CloudKitSchemaInitializer {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--init-cloudkit-schema") else { return }
        let environment = entitlement("com.apple.developer.icloud-container-environment") as? String
        guard environment == "Development" else {
            print("✗ This build's CloudKit environment is \(environment ?? "unset"), not Development. " +
                  "Re-sign with icloud-container-environment = Development.")
            exit(1)
        }
        do {
            try initialize()
            print("✓ CloudKit schema initialized in Development for \(DorisIdentifiers.cloudKitContainer)")
            exit(0)
        } catch {
            print("✗ initializeCloudKitSchema failed: \(error)")
            exit(1)
        }
    }

    private static func initialize() throws {
        let types: [any PersistentModel.Type] = [
            Folder.self, Note.self, ChecklistItem.self,
            Tag.self, Attachment.self, Message.self,
            Device.self, UserSettings.self,
        ]
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: types) else {
            throw NSError(domain: "CloudKitSchemaInitializer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "could not build the Core Data model"])
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("doris-schema-init-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let description = NSPersistentStoreDescription(url: dir.appendingPathComponent("Schema.sqlite"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: DorisIdentifiers.cloudKitContainer)
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "Doris", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        try container.initializeCloudKitSchema(options: [])

        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    private static func entitlement(_ key: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }
}
#endif
