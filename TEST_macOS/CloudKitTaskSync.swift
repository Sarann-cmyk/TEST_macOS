//
//  CloudKitTaskSync.swift
//  TEST_macOS
//

import CloudKit
import Combine
import CoreData
import Foundation

@MainActor
final class CloudKitTaskSync: ObservableObject {
    static let shared = CloudKitTaskSync()

    private let containerID = PersistenceController.cloudKitContainerIdentifier
    private let zoneName = "com.apple.coredata.cloudkit.zone"
    private let recordType = "CD_TaskItem"
    private let mapDefaultsKey = "cloudKitRecordNameByTaskKey"
    private let knownRecordsKey = "knownCloudKitRecordNames"
    private let pollingIntervalSeconds = 5.0

    private var pollingTask: Task<Void, Never>?
    private var isMutating = false

    func startPolling(viewContext: NSManagedObjectContext, syncMonitor: CloudKitSyncMonitor) {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await pullFromCloud(viewContext: viewContext, syncMonitor: syncMonitor)
                try? await Task.sleep(for: .seconds(pollingIntervalSeconds))
            }
        }
    }

    func pullFromCloud(viewContext: NSManagedObjectContext, syncMonitor: CloudKitSyncMonitor) async {
        guard !isMutating else {
            print("[CloudKit] Skipping sync — local change in progress")
            return
        }

        do {
            let fetchResult = try await fetchAllTaskRecords()
            switch fetchResult {
            case .records(let records):
                reconcile(records: records, viewContext: viewContext, allowDeletions: true)
                syncMonitor.statusMessage = "Синхронізовано: \(records.count) задач(і) в iCloud"
                print("[CloudKit] Synced \(records.count) record(s) from CloudKit")
            case .transientEmpty:
                print("[CloudKit] Fetch unavailable — keeping local state")
            }
        } catch {
            syncMonitor.statusMessage = "Помилка синхронізації: \(error.localizedDescription)"
            print("[CloudKit] Sync failed: \(error)")
        }
    }

    func createTask(title: String, viewContext: NSManagedObjectContext) async throws {
        isMutating = true
        defer { isMutating = false }

        let createdAt = Date()
        let zoneID = CKRecordZone.ID(zoneName: zoneName)
        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["CD_title"] = title
        record["CD_createdAt"] = createdAt
        record["CD_entityName"] = "TaskItem"

        let database = CKContainer(identifier: containerID).privateCloudDatabase
        _ = try await database.save(record)

        let task = TaskItem(context: viewContext)
        task.title = title
        task.createdAt = createdAt
        saveRecordName(recordID.recordName, for: task)
        addKnownRecordName(recordID.recordName)
        PersistenceController.save(viewContext, operation: "create task")
        print("[CloudKit] Created record \(recordID.recordName)")
    }

    func deleteTask(_ task: TaskItem, viewContext: NSManagedObjectContext) async throws {
        isMutating = true
        defer { isMutating = false }

        if let recordName = recordName(for: task) {
            let recordID = CKRecord.ID(
                recordName: recordName,
                zoneID: CKRecordZone.ID(zoneName: zoneName)
            )
            let database = CKContainer(identifier: containerID).privateCloudDatabase
            _ = try await database.deleteRecord(withID: recordID)
            removeMapping(forRecordName: recordName)
            removeKnownRecordName(recordName)
            print("[CloudKit] Deleted record \(recordName)")
        }

        viewContext.delete(task)
        PersistenceController.save(viewContext, operation: "delete task")
    }

    // MARK: - Private

    private enum FetchResult {
        case records([CKRecord])
        case transientEmpty
    }

    private func fetchAllTaskRecords() async throws -> FetchResult {
        let database = CKContainer(identifier: containerID).privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: zoneName)
        let knownNames = knownRecordNames().union(Set(map().values))

        var discovered = try await queryRecordsWithRetry(database: database, zoneID: zoneID)

        var recordNames = knownNames
        recordNames.formUnion(discovered.map(\.recordID.recordName))

        if recordNames.isEmpty {
            return .transientEmpty
        }

        let fetchedByID = try await fetchRecordsByName(Array(recordNames), database: database, zoneID: zoneID)
        var merged = Dictionary(uniqueKeysWithValues: fetchedByID.map { ($0.recordID.recordName, $0) })
        for record in discovered {
            merged[record.recordID.recordName] = record
        }

        let records = Array(merged.values)

        if records.isEmpty, !knownNames.isEmpty {
            // Known records are gone from CloudKit — real empty state.
            return .records([])
        }

        if records.isEmpty {
            return .transientEmpty
        }

        return .records(records)
    }

    private func queryRecordsWithRetry(database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        for attempt in 1...3 {
            let records = try await queryRecords(database: database, zoneID: zoneID)
            if !records.isEmpty {
                return records
            }
            if attempt < 3 {
                try await Task.sleep(for: .milliseconds(600 * attempt))
            }
        }
        return []
    }

    private func queryRecords(database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        let query = CKQuery(
            recordType: recordType,
            predicate: NSPredicate(format: "CD_entityName == %@", "TaskItem")
        )

        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let matchResults: [(CKRecord.ID, Result<CKRecord, Error>)]
            let nextCursor: CKQueryOperation.Cursor?

            if let cursor {
                (matchResults, nextCursor) = try await database.records(
                    continuingMatchFrom: cursor,
                    desiredKeys: ["CD_title", "CD_createdAt", "CD_entityName"]
                )
            } else {
                (matchResults, nextCursor) = try await database.records(
                    matching: query,
                    inZoneWith: zoneID,
                    desiredKeys: ["CD_title", "CD_createdAt", "CD_entityName"]
                )
            }

            for (_, result) in matchResults {
                if case .success(let record) = result {
                    allRecords.append(record)
                }
            }

            cursor = nextCursor
        } while cursor != nil

        return allRecords
    }

    private func fetchRecordsByName(
        _ names: [String],
        database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> [CKRecord] {
        guard !names.isEmpty else { return [] }

        var records: [CKRecord] = []
        let batchSize = 100

        for batchStart in stride(from: 0, to: names.count, by: batchSize) {
            let batch = Array(names[batchStart..<min(batchStart + batchSize, names.count)])
            let ids = batch.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
            let results = try await database.records(
                for: ids,
                desiredKeys: ["CD_title", "CD_createdAt", "CD_entityName"]
            )

            for (_, result) in results {
                switch result {
                case .success(let record):
                    records.append(record)
                case .failure(let error as CKError) where error.code == CKError.Code.unknownItem:
                    continue
                case .failure(let error):
                    print("[CloudKit] Fetch by ID error: \(error)")
                }
            }
        }

        return records
    }

    private func reconcile(
        records: [CKRecord],
        viewContext: NSManagedObjectContext,
        allowDeletions: Bool
    ) {
        var seenRecordNames = Set<String>()
        var changed = false

        for record in records {
            let recordName = record.recordID.recordName
            seenRecordNames.insert(recordName)

            let title = record["CD_title"] as? String
            let createdAt = record["CD_createdAt"] as? Date

            if let existing = findTask(cloudRecordName: recordName, title: title, createdAt: createdAt, viewContext: viewContext) {
                if existing.title != title { existing.title = title; changed = true }
                if existing.createdAt != createdAt { existing.createdAt = createdAt; changed = true }
                saveRecordName(recordName, for: existing)
            } else {
                let task = TaskItem(context: viewContext)
                task.title = title
                task.createdAt = createdAt
                saveRecordName(recordName, for: task)
                changed = true
            }
        }

        saveKnownRecordNames(seenRecordNames)

        guard allowDeletions else { return }

        let localTasks = (try? viewContext.fetch(TaskItem.fetchRequest())) ?? []
        for task in localTasks {
            guard let recordName = recordName(for: task) else { continue }
            if !seenRecordNames.contains(recordName) {
                viewContext.delete(task)
                removeMapping(forRecordName: recordName)
                removeKnownRecordName(recordName)
                changed = true
            }
        }

        if changed {
            PersistenceController.save(viewContext, operation: "reconcile")
        }
    }

    private func findTask(
        cloudRecordName: String,
        title: String?,
        createdAt: Date?,
        viewContext: NSManagedObjectContext
    ) -> TaskItem? {
        let tasks = (try? viewContext.fetch(TaskItem.fetchRequest())) ?? []

        if let taskKey = map().first(where: { $0.value == cloudRecordName })?.key,
           let titlePart = taskKey.split(separator: "|", maxSplits: 1).first.map(String.init),
           let datePart = taskKey.split(separator: "|", maxSplits: 1).last.flatMap(Double.init),
           let match = tasks.first(where: {
               ($0.title ?? "") == titlePart && $0.createdAt?.timeIntervalSince1970 == datePart
           }) {
            return match
        }

        return tasks.first {
            $0.title == title && $0.createdAt == createdAt
        }
    }

    private func taskKey(for task: TaskItem) -> String {
        let title = task.title ?? ""
        let date = task.createdAt?.timeIntervalSince1970 ?? 0
        return "\(title)|\(date)"
    }

    private func recordName(for task: TaskItem) -> String? {
        map()[taskKey(for: task)]
    }

    private func saveRecordName(_ recordName: String, for task: TaskItem) {
        var current = map()
        current[taskKey(for: task)] = recordName
        UserDefaults.standard.set(current, forKey: mapDefaultsKey)
        addKnownRecordName(recordName)
    }

    private func removeMapping(forRecordName recordName: String) {
        var current = map()
        if let key = current.first(where: { $0.value == recordName })?.key {
            current.removeValue(forKey: key)
            UserDefaults.standard.set(current, forKey: mapDefaultsKey)
        }
    }

    private func map() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: mapDefaultsKey) as? [String: String] ?? [:]
    }

    private func knownRecordNames() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: knownRecordsKey) ?? [])
    }

    private func saveKnownRecordNames(_ names: Set<String>) {
        UserDefaults.standard.set(Array(names), forKey: knownRecordsKey)
    }

    private func addKnownRecordName(_ name: String) {
        var names = knownRecordNames()
        names.insert(name)
        saveKnownRecordNames(names)
    }

    private func removeKnownRecordName(_ name: String) {
        var names = knownRecordNames()
        names.remove(name)
        saveKnownRecordNames(names)
    }
}
