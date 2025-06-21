//
//  avanteApp.swift
//  avante
//
//  Created by Carl Osborne on 6/19/25.
//

import SwiftUI

@main
struct avanteApp: App {
    @StateObject private var workspace = WorkspaceViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(workspace: workspace)
                .onOpenURL { url in
                    workspace.openFile(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    workspace.openAnyFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveAction, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let saveAction = Notification.Name("com.example.vnt.saveAction")
}
