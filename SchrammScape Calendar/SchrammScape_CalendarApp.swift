//
//  SchrammScape_CalendarApp.swift
//  SchrammScape Calendar
//
//  Created by Tim Schramm on 7/1/26.
//

import SwiftUI
import SwiftData
import CoreData

@main
struct SchrammScape_CalendarApp: App {
    let container: ModelContainer

    private static let modelTypes: [any PersistentModel.Type] = [
        Customer.self, WorkRecord.self, ServiceItem.self,
        JobType.self, Invoice.self, MileageEntry.self
    ]

    private static let cloudKitContainerID = "iCloud.com.schrammscape.SchrammScape-Calendar"

    init() {
        let schema = Schema(Self.modelTypes)
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        do {
            #if DEBUG
            // Push the model schema to CloudKit's development environment so the
            // record types exist before the first sync (Apple's documented recipe).
            try Self.initializeCloudKitDevelopmentSchema(config: config, schema: schema)
            #endif
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        JobAlertService.shared.setUp(container: container)
    }

    #if DEBUG
    private static func initializeCloudKitDevelopmentSchema(config: ModelConfiguration, schema: Schema) throws {
        try autoreleasepool {
            let description = NSPersistentStoreDescription(url: config.url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerID
            )
            description.shouldAddStoreAsynchronously = false
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: modelTypes) else { return }
            let cloudContainer = NSPersistentCloudKitContainer(
                name: "SchrammScape",
                managedObjectModel: model
            )
            cloudContainer.persistentStoreDescriptions = [description]
            var loadError: Error?
            cloudContainer.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }
            try cloudContainer.initializeCloudKitSchema()
            // Unload so SwiftData can take over the same store file.
            if let store = cloudContainer.persistentStoreCoordinator.persistentStores.first {
                try cloudContainer.persistentStoreCoordinator.remove(store)
            }
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
