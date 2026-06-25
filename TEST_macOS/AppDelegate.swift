//
//  AppDelegate.swift
//  TEST_macOS
//
//  Created by Aleks Synelnyk on 25.06.2026.
//

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // NSPersistentCloudKitContainer uses this token automatically
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Push] Registration failed: \(error)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        // NSPersistentCloudKitContainer handles CloudKit silent pushes automatically
    }
}
