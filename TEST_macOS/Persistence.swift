//
//  Persistence.swift
//  TEST_macOS
//
//  Created by Aleks Synelnyk on 25.06.2026.
//

import Combine
import CoreData
import SwiftUI

@MainActor
final class CloudKitSyncMonitor: ObservableObject {
    @Published var statusMessage = "Синхронізація з iCloud…"
}

struct PersistenceController {
    @MainActor static let shared = PersistenceController()
    static let cloudKitContainerIdentifier = "iCloud.WINNER.ltd.TEST-iOS"

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for index in 1...5 {
            let task = TaskItem(context: viewContext)
            task.title = "Task \(index)"
            task.createdAt = Date()
        }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("[CoreData] Preview save failed: \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer
    @MainActor let syncMonitor = CloudKitSyncMonitor()

    @MainActor
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "TEST_iOS")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                print("[CoreData] Failed to load store: \(error), \(error.userInfo)")
            } else {
                print("[CoreData] Store loaded (local cache)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    @discardableResult
    static func save(_ context: NSManagedObjectContext, operation: String) -> Bool {
        guard context.hasChanges else { return true }

        do {
            try context.save()
            return true
        } catch {
            let nsError = error as NSError
            context.rollback()
            print("[CoreData] Failed to \(operation): \(nsError), \(nsError.userInfo)")
            return false
        }
    }
}
