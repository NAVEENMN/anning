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

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…") { _ = appDelegate.menuNewProject() }
                    .keyboardShortcut("n", modifiers: [.command])

                Button("Open Project…") { _ = appDelegate.menuOpenProject() }
                    .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") { _ = appDelegate.menuSave() }
                    .keyboardShortcut("s", modifiers: [.command])

                Button("Save As…") { _ = appDelegate.menuSaveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
