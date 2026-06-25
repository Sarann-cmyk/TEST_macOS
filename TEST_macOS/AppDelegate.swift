//
//  AppDelegate.swift
//  TEST_macOS
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
        print("[CloudKit] Registered for remote notifications")
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("[CloudKit] Push token received (\(deviceToken.count) bytes)")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[CloudKit] Push registration failed: \(error.localizedDescription)")
        print("[CloudKit] Синхронізація через polling кожні 5 сек (push не обовʼязковий)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        print("[CloudKit] Remote notification received")
        Task { @MainActor in
            await CloudKitTaskSync.shared.pullFromCloud(
                viewContext: PersistenceController.shared.container.viewContext,
                syncMonitor: PersistenceController.shared.syncMonitor
            )
        }
    }
}
