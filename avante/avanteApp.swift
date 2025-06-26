//
//  avanteApp.swift
//  avante
//
//  Created by Carl Osborne on 6/19/25.
//

import SwiftUI
import FoundationModels

@main
struct avanteApp: App {
    @StateObject private var workspace = WorkspaceViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(workspace: workspace)
                .onOpenURL { url in
                    // FIX: The method was renamed from 'openFile' to 'open'.
                    // This is the corrected method call.
                    workspace.open(url: url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // This CommandGroup replaces the default "File > New" (Cmd+N) menu item.
            CommandGroup(replacing: .newItem) {
                // We point it to our custom open function instead.
                Button("Open...") {
                    workspace.openFileOrFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            // This CommandGroup replaces the default "File > Save" (Cmd+S) menu item.
            CommandGroup(replacing: .saveItem) {
                // It posts a notification, which the EditView listens for.
                // This decouples the App scene from the specific view doing the saving.
                Button("Save") {
                    NotificationCenter.default.post(name: .saveAction, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandMenu("Navigation") {
                Button("Next File") {
                    workspace.selectNextFile()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                
                Button("Previous File") {
                    workspace.selectPreviousFile()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            }
        }
    }
}

// Defines a custom Notification name for the save action.
extension Notification.Name {
    static let saveAction = Notification.Name("com.carlosborne.avante.saveAction")
}
