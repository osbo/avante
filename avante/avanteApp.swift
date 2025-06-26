//
//  avanteApp.swift
//  avante
//
//  Created by Carl Osborne on 6/19/25.
//

import SwiftUI
import FoundationModels
import Combine

@main
struct avanteApp: App {
    @StateObject private var workspace = WorkspaceViewModel()
    @AppStorage("activeHighlight") private var activeHighlightRaw: String = ""

    var body: some Scene {
        let currentHighlight = MetricType(rawValue: activeHighlightRaw)
        return WindowGroup {
            ContentView(workspace: workspace)
                .onOpenURL { url in
                    // FIX: The method was renamed from 'openFile' to 'open'.
                    // This is the corrected method call.
                    workspace.open(url: url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("New File") {
                    workspace.createNewFile(in: workspace.selectedItem)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("New Folder") {
                    workspace.createNewFolder(in: workspace.selectedItem)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Open...") {
                    workspace.openFileOrFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveAction, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            
            // Add rename functionality to File menu
            CommandGroup(after: .saveItem) {
                Button("Rename") {
                    NotificationCenter.default.post(name: .renameAction, object: workspace.selectedItem)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            
            // View Menu with dial functionality
            CommandMenu("View") {
                HighlightMenuItems(activeHighlightRaw: $activeHighlightRaw)
            }
            
            // Navigation Menu
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

// Defines custom Notification names for various actions
extension Notification.Name {
    static let saveAction = Notification.Name("com.carlosborne.avante.saveAction")
    static let renameAction = Notification.Name("com.carlosborne.avante.renameAction")
    static let toggleHighlight = Notification.Name("com.carlosborne.avante.toggleHighlight")
    static let clearHighlights = Notification.Name("com.carlosborne.avante.clearHighlights")
    static let triggerRename = Notification.Name("com.carlosborne.avante.triggerRename")
}

struct HighlightMenuItems: View {
    @Binding var activeHighlightRaw: String

    var body: some View {
        let currentHighlight = MetricType(rawValue: activeHighlightRaw)
        ForEach(Array(MetricType.preferredOrder.enumerated()), id: \.element) { idx, type in
            Toggle(
                "\(type.rawValue.capitalized) Highlight",
                isOn: Binding(
                    get: { currentHighlight == type },
                    set: { isOn in
                        activeHighlightRaw = isOn ? type.rawValue : ""
                    }
                )
            )
            .keyboardShortcut(KeyEquivalent(Character("\(idx+1)")), modifiers: .command)
        }
    }
}
