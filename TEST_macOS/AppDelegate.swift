//
//  AppDelegate.swift
//  TEST_macOS
//
//  Created by Aleks Synelnyk on 25.06.2026.
//

import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                NSApp.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // NSPersistentCloudKitContainer uses this token automatically
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Remote notification registration failed: \(error)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        // NSPersistentCloudKitContainer handles CloudKit silent pushes automatically
    }
}
