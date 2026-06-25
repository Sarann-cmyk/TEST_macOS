//
//  TEST_macOSApp.swift
//  TEST_macOS
//
//  Created by Aleks Synelnyk on 25.06.2026.
//

import SwiftUI
import CoreData

@main
struct TEST_macOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
