//
//  anningApp.swift
//  anning
//
//  Created by Naveen Mysore on 1/5/26.
//

import SwiftUI
import CoreData

@main
struct anningApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
