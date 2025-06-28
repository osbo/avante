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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var workspace = WorkspaceViewModel()
    @AppStorage("activeHighlight") private var activeHighlightRaw: String = ""
    @AppStorage("isFocusModeEnabled") private var isFocusModeEnabled: Bool = false

    var body: some Scene {
        Window("Avante", id: "com.carlosborne.avante.main-window") {
            ContentView(workspace: workspace, isFocusModeEnabled: $isFocusModeEnabled)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("New File") {
                    workspace.createNewFile(in: workspace.selectedItem)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(workspace.isSingleFileMode)
                
                Button("New Folder") {
                    workspace.createNewFolder(in: workspace.selectedItem)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(workspace.isSingleFileMode)
                
                Divider()
                
                Button("Open...") {
                    workspace.openFileOrFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("Close") {
                    if workspace.rootItem != nil {
                        workspace.clearSession()
                    } else {
                        NSApp.keyWindow?.close()
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveAction, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            
            // File editing operations
            CommandGroup(after: .saveItem) {
                Button("Rename") {
                    NotificationCenter.default.post(name: .renameAction, object: workspace.selectedItem)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                
                Button("Delete") {
                    if let itemToDelete = workspace.selectedItem {
                        workspace.deleteItem(itemToDelete)
                    }
                }
                .disabled(workspace.selectedItem == nil || workspace.isSingleFileMode)
                
                Divider()
                
                Button("Re-analyze File") {
                    if let selectedFile = workspace.selectedFileForEditor {
                         NotificationCenter.default.post(name: .reanalyzeAction, object: selectedFile)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(workspace.selectedFileForEditor == nil)
            }
            
            // View Menu with dial functionality
            CommandMenu("View") {
                Toggle(
                    "Focus Mode",
                    isOn: $isFocusModeEnabled
                )
                .keyboardShortcut("e", modifiers: .command)
                
                Divider()
                
                HighlightMenuItems(activeHighlightRaw: $activeHighlightRaw)
            }
            
            // Navigation Menu
            CommandMenu("Navigation") {
                Button("Next File") {
                    workspace.selectNextFile()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(workspace.isSingleFileMode || workspace.selectedFileForEditor == nil)
                
                Button("Previous File") {
                    workspace.selectPreviousFile()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(workspace.isSingleFileMode || workspace.selectedFileForEditor == nil)
            }
        }
    }
}

// FIX: The Notification.Name extension has been moved to SharedTypes.swift
// to resolve a Swift 6 concurrency warning.

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
