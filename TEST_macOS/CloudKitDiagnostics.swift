//
//  CloudKitDiagnostics.swift
//  TEST_macOS
//

import CloudKit

@MainActor
enum CloudKitDiagnostics {
    private static let coreDataZoneName = "com.apple.coredata.cloudkit.zone"

    static func run(containerID: String, syncMonitor: CloudKitSyncMonitor) async {
        let container = CKContainer(identifier: containerID)

        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                print("[CloudKit] iCloud account available")
            case .noAccount:
                syncMonitor.statusMessage = "Увійдіть в iCloud: System Settings → Apple ID"
                print("[CloudKit] No iCloud account on this Mac")
                return
            case .restricted:
                syncMonitor.statusMessage = "iCloud обмежений на цьому Mac"
                return
            case .couldNotDetermine:
                syncMonitor.statusMessage = "Не вдалося перевірити статус iCloud"
                return
            case .temporarilyUnavailable:
                syncMonitor.statusMessage = "iCloud тимчасово недоступний"
                return
            @unknown default:
                syncMonitor.statusMessage = "Невідомий статус iCloud"
                return
            }

            let userID = try await container.userRecordID()
            print("[CloudKit] User record: \(userID.recordName)")

            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(zoneName: coreDataZoneName)
            let query = CKQuery(
                recordType: "CD_TaskItem",
                predicate: NSPredicate(format: "CD_entityName == %@", "TaskItem")
            )

            let (matchResults, _) = try await database.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: ["CD_title", "CD_createdAt", "CD_entityName"]
            )

            let recordCount = matchResults.count
            print("[CloudKit] CD_TaskItem records in CloudKit: \(recordCount)")

            for (_, result) in matchResults {
                if case .failure(let error) = result {
                    print("[CloudKit] Record error: \(error)")
                }
            }

            if recordCount == 0 {
                syncMonitor.statusMessage = "У CloudKit 0 задач для цього Apple ID"
            } else {
                for (_, result) in matchResults {
                    if case .success(let record) = result {
                        print("[CloudKit] Record: \(record["CD_title"] ?? "nil")")
                    }
                }
                syncMonitor.statusMessage = "У CloudKit \(recordCount) задач(і). Очікую імпорт у Core Data…"
            }
        } catch let error as CKError {
            print("[CloudKit] CKError \(error.code.rawValue): \(error.localizedDescription)")
            if let partial = error.partialErrorsByItemID {
                for (id, err) in partial {
                    print("[CloudKit] Partial error for \(id): \(err)")
                }
            }

            switch error.code {
            case .notAuthenticated:
                syncMonitor.statusMessage = "Увійдіть в iCloud на цьому Mac"
            case .permissionFailure:
                syncMonitor.statusMessage = "Немає доступу до контейнера. Додай WINNER.ltd.TEST-macOS у CloudKit Containers на developer.apple.com"
            default:
                syncMonitor.statusMessage = "CloudKit: \(error.localizedDescription)"
            }
        } catch {
            print("[CloudKit] Error: \(error)")
            syncMonitor.statusMessage = "Помилка: \(error.localizedDescription)"
        }
    }
}
