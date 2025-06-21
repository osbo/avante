//
//  WorkspaceViewModel.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import Foundation
import SwiftUI
import Combine

private enum UserDefaultsKeys {
    static let workspaceBookmark = "workspaceBookmark"
    static let selectedFileBookmark = "selectedFileBookmark"
}

@MainActor
class WorkspaceViewModel: ObservableObject {
    @Published var workspaceRootUrl: URL?
    @Published var selectedFileUrl: URL? {
        didSet {
            saveSelectedFileBookmark()
        }
    }
    @Published var fileTree: [FileItem] = []
    @Published var selectedItem: FileItem?
    @Published var expandedItemIDs = Set<URL>()
    
    init() {
        restoreWorkspace()
    }
    
    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            setWorkspace(url: url)
        }
    }
    
    func openFile(_ url: URL) {
        let workspaceUrl = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        setWorkspace(url: workspaceUrl)
        
        if !url.hasDirectoryPath {
            self.selectedFileUrl = url
        }
    }
    
    func openAnyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.vnt]

        if panel.runModal() == .OK, let url = panel.url {
            openFile(url)
        }
    }
    
    private func restoreWorkspace() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: UserDefaultsKeys.workspaceBookmark) else { return }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                // Handle stale bookmark if necessary, maybe by creating a new one
                print("Workspace bookmark is stale.")
            }
            
            setWorkspace(url: url)
            let previouslySelected = self.selectedFileUrl
            self.fileTree = buildFileTree(from: url)
            // We don't restore selection here because the NSOutlineView will do it.
            // self.selectedFileUrl = previouslySelected
            
        } catch {
            print("Error restoring workspace from bookmark: \(error)")
        }
    }
    
    private func restoreSelectedFile() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: UserDefaultsKeys.selectedFileBookmark) else { return }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("Selected file bookmark is stale.")
            }
            
            if url.startAccessingSecurityScopedResource() {
                self.selectedFileUrl = url
            }
        } catch {
            print("Error restoring selected file from bookmark: \(error)")
        }
    }
    
    private func saveSelectedFileBookmark() {
        guard let url = selectedFileUrl else {
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.selectedFileBookmark)
            return
        }

        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: UserDefaultsKeys.selectedFileBookmark)
        } catch {
            print("Failed to save selected file bookmark: \(error)")
        }
    }

    private func setWorkspace(url: URL) {
        // When setting a new workspace, clear the old file selection bookmark
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.selectedFileBookmark)
        
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to start accessing security-scoped resource.")
            return
        }

        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: UserDefaultsKeys.workspaceBookmark)
        } catch {
            print("Failed to save workspace bookmark: \(error)")
        }

        self.workspaceRootUrl = url
        self.refreshFileTree()
    }
    
    private func buildFileTree(from url: URL) -> [FileItem] {
        var items: [FileItem] = []
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            
            for itemUrl in contents {
                if !itemUrl.hasDirectoryPath && itemUrl.pathExtension != "vnt" {
                    continue
                }
                
                let isDirectory = (try? itemUrl.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                
                let fileItem = FileItem(url: itemUrl)
                if fileItem.isFolder && self.expandedItemIDs.contains(itemUrl) {
                    fileItem.children = buildFileTree(from: itemUrl)
                    fileItem.isExpanded = true
                }
                items.append(fileItem)
            }
        } catch {
            print("Error building file tree: \(error)")
        }
        
        items.sort { $0.isFolder && !$1.isFolder || ($0.isFolder == $1.isFolder && $0.name.localizedStandardCompare($1.name) == .orderedAscending) }
        
        return items
    }
    
    func loadChildren(for item: FileItem) {
        guard item.isFolder, item.children?.isEmpty ?? true else { return }
        item.children = buildFileTree(from: item.id)
    }

    func renameItem(_ item: FileItem, to newName: String) {
        let newUrl = item.id.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: item.id, to: newUrl)
            refreshFileTree()
        } catch {
            print("Error renaming item: \(error)")
        }
    }

    func deleteItem(_ item: FileItem) {
        do {
            try FileManager.default.removeItem(at: item.id)
            refreshFileTree()
        } catch {
            print("Error deleting item: \(error)")
        }
    }

    func createNewFile(in directoryItem: FileItem? = nil) {
        let parentUrl: URL
        if let directoryItem = directoryItem, directoryItem.isFolder {
            parentUrl = directoryItem.id
        } else if let directoryItem = directoryItem {
            parentUrl = directoryItem.id.deletingLastPathComponent()
        } else {
            parentUrl = workspaceRootUrl!
        }

        var fileName = "Untitled.vnt"
        var counter = 1
        var newFileUrl = parentUrl.appendingPathComponent(fileName)

        while FileManager.default.fileExists(atPath: newFileUrl.path) {
            counter += 1
            fileName = "Untitled \(counter).vnt"
            newFileUrl = parentUrl.appendingPathComponent(fileName)
        }

        let emptyDoc = AvanteFile(text: "", analysis: [])
        do {
            let data = try JSONEncoder().encode(emptyDoc)
            if FileManager.default.createFile(atPath: newFileUrl.path, contents: data) {
                print("Created new file: \(fileName)")
                refreshFileTree()
            }
        } catch {
            print("Error creating new file: \(error)")
        }
    }

    func createNewFolder(in directoryItem: FileItem? = nil) {
        let parentUrl: URL
        if let directoryItem = directoryItem, directoryItem.isFolder {
            parentUrl = directoryItem.id
        } else if let directoryItem = directoryItem {
            parentUrl = directoryItem.id.deletingLastPathComponent()
        } else {
            parentUrl = workspaceRootUrl!
        }

        var folderName = "Untitled Folder"
        var counter = 1
        var newFolderUrl = parentUrl.appendingPathComponent(folderName)

        while FileManager.default.fileExists(atPath: newFolderUrl.path) {
            counter += 1
            folderName = "Untitled Folder \(counter)"
            newFolderUrl = parentUrl.appendingPathComponent(folderName)
        }

        do {
            try FileManager.default.createDirectory(at: newFolderUrl, withIntermediateDirectories: false)
            print("Created new folder: \(folderName)")
            refreshFileTree()
        } catch {
            print("Error creating new folder: \(error)")
        }
    }
    
    private func refreshFileTree() {
        guard let url = workspaceRootUrl else { return }
        self.fileTree = buildFileTree(from: url)
    }
} 