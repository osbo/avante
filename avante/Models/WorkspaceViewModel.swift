//
//  WorkspaceViewModel.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

private enum UserDefaultsKeys {
    static let workspaceBookmark = "workspaceBookmark"
}

@MainActor
class WorkspaceViewModel: ObservableObject {
    @Published var rootItem: FileItem?
    @Published var selectedItem: FileItem? {
        didSet {
            if let item = selectedItem, !item.isFolder {
                self.selectedFileForEditor = item
            } else {
                self.selectedFileForEditor = nil
            }
        }
    }
    @Published var selectedFileForEditor: FileItem?
    
    private var isPerformingManualFileOperation = false
    
    private var openFileViewModels: [URL: AnalysisViewModel] = [:]
    
    private var expandedItemURLs = Set<URL>()
    private var fileSystemMonitor = FileSystemMonitor()
    private var securityScopedURL: URL?
    
    init() {
        restoreWorkspace()
        setupFileSystemMonitoring()
    }
    
    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }
    
    private func setupFileSystemMonitoring() {
        fileSystemMonitor.changeHandler = { [weak self] in
            guard let self = self, !self.isPerformingManualFileOperation else {
                print("Ignoring file system change due to manual operation.")
                return
            }
            print("File system change detected, refreshing tree.")
            self.refreshFileTree()
        }
    }

    // MARK: Public API
    func viewModel(for fileItem: FileItem) -> AnalysisViewModel {
        // If a view model for this URL already exists in our cache, return it.
        if let cachedViewModel = openFileViewModels[fileItem.url] {
            return cachedViewModel
        }
        
        // Otherwise, create a new one, add it to the cache, and return it.
        let newViewModel = AnalysisViewModel(fileUrl: fileItem.url)
        openFileViewModels[fileItem.url] = newViewModel
        return newViewModel
    }
    
    func openFileOrFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType("com.example.vnt")!, .folder]
        if panel.runModal() == .OK, let url = panel.url { open(url: url) }
    }
    
    func open(url: URL) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let workspaceUrl = isDirectory ? url : url.deletingLastPathComponent()
        setWorkspace(url: workspaceUrl)
        if !isDirectory {
            DispatchQueue.main.async { [weak self] in
                self?.selectFile(at: url)
            }
        }
    }
    
    func createNewFile(in parent: FileItem?) {
        let parentItem = determineParent(for: parent)
        if !parentItem.isExpanded { toggleExpansion(for: parentItem) }
        
        self.isPerformingManualFileOperation = true
        
        Task {
            if let newURL = await createUniqueItem(in: parentItem, baseName: "Untitled", isFolder: false) {
                let newItem = FileItem(url: newURL); newItem.parent = parentItem
                parentItem.children?.append(newItem)
                parentItem.children?.sort { ($0.isFolder && !$1.isFolder) || ($0.isFolder == $1.isFolder && $0.name.localizedStandardCompare($1.name) == .orderedAscending) }
                
                // This is the key line: setting the selection opens the file in the editor,
                // which will now correctly receive focus.
                self.selectedItem = newItem
                
                // FIX: The call to initiate renaming has been removed.
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isPerformingManualFileOperation = false
            }
        }
    }
    
    func createNewFolder(in parent: FileItem?) {
        let parentItem = determineParent(for: parent)
        if !parentItem.isExpanded { toggleExpansion(for: parentItem) }

        self.isPerformingManualFileOperation = true
        
        Task {
            if let newURL = await createUniqueItem(in: parentItem, baseName: "Untitled Folder", isFolder: true) {
                let newItem = FileItem(url: newURL); newItem.parent = parentItem
                parentItem.children?.append(newItem)
                parentItem.children?.sort { ($0.isFolder && !$1.isFolder) || ($0.isFolder == $1.isFolder && $0.name.localizedStandardCompare($1.name) == .orderedAscending) }
                self.selectedItem = newItem
                // FIX: The call to initiate renaming has been removed.
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isPerformingManualFileOperation = false
            }
        }
    }
    
    func renameItem(_ item: FileItem, to newName: String) {
        self.isPerformingManualFileOperation = true
        let oldURL = item.url
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        
        Task {
            do {
                try await Task.detached { try FileManager.default.moveItem(at: oldURL, to: newURL) }.value
                item.url = newURL
                
                if let viewModel = self.openFileViewModels.removeValue(forKey: oldURL) {
                    viewModel.document.updateURL(to: newURL)
                    self.openFileViewModels[newURL] = viewModel
                }
                
                refreshFileTree()
            } catch { print("Error renaming item: \(error)") }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isPerformingManualFileOperation = false
            }
        }
    }
    
    func deleteItem(_ item: FileItem) {
        if selectedItem == item { selectedItem = nil }
        self.isPerformingManualFileOperation = true
        let urlToDelete = item.url
        
        Task {
            do {
                try await Task.detached { try FileManager.default.removeItem(at: urlToDelete) }.value
                
                self.openFileViewModels.removeValue(forKey: urlToDelete)
                
                refreshFileTree()
            } catch { print("Error deleting item: \(error)") }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isPerformingManualFileOperation = false
            }
        }
    }
    
    func toggleExpansion(for item: FileItem) {
        item.isExpanded.toggle()
        if item.isExpanded {
            expandedItemURLs.insert(item.url)
            if item.children?.isEmpty ?? true { item.children = buildFileTree(from: item.url, parent: item) }
        } else {
            expandedItemURLs.remove(item.url)
        }
        objectWillChange.send()
    }

    // MARK: - Workspace and Tree Management
    private func setWorkspace(url: URL) {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to start accessing security-scoped resource. Check App Sandbox Entitlements.")
            return
        }
        
        // Keep track of the URL we are now accessing.
        self.securityScopedURL = url
        
        saveWorkspaceBookmark(url)
        self.rootItem = FileItem(url: url)
        self.rootItem?.isExpanded = true
        refreshFileTree()
        fileSystemMonitor.startMonitoring(path: url.path)
    }

    func refreshFileTree() {
        guard let root = rootItem else { return }
        let oldSelectionURL = selectedItem?.url
        root.children = buildFileTree(from: root.url, parent: root)
        objectWillChange.send()
        if let oldURL = oldSelectionURL { selectFile(at: oldURL) }
    }
    
    private func buildFileTree(from url: URL, parent: FileItem?) -> [FileItem] {
        var items: [FileItem] = []
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .nameKey], options: .skipsHiddenFiles)
            for itemUrl in contents {
                let isDirectory = (try? itemUrl.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if !isDirectory && itemUrl.pathExtension != "vnt" { continue }
                let fileItem = FileItem(url: itemUrl); fileItem.parent = parent
                if fileItem.isFolder, expandedItemURLs.contains(itemUrl) {
                    fileItem.isExpanded = true
                    fileItem.children = buildFileTree(from: itemUrl, parent: fileItem)
                }
                items.append(fileItem)
            }
        } catch { print("Error building file tree: \(error)") }
        items.sort { ($0.isFolder && !$1.isFolder) || ($0.isFolder == $1.isFolder && $0.name.localizedStandardCompare($1.name) == .orderedAscending) }
        return items
    }
    
    // MARK: - Helpers
    private func determineParent(for item: FileItem?) -> FileItem {
        guard let item = item else { return rootItem! }
        return item.isFolder ? item : item.parent ?? rootItem!
    }
    
    private func createUniqueItem(in parent: FileItem, baseName: String, isFolder: Bool) async -> URL? {
        // ... (This function remains the same)
        let parentUrl = parent.url
        let pathExtension = isFolder ? "" : "vnt"
        return await Task.detached {
            var counter = 1
            var finalName = pathExtension.isEmpty ? baseName : "\(baseName).\(pathExtension)"
            var newURL = parentUrl.appendingPathComponent(finalName)
            while FileManager.default.fileExists(atPath: newURL.path) {
                counter += 1
                let newBaseName = "\(baseName) \(counter)"
                finalName = pathExtension.isEmpty ? newBaseName : "\(newBaseName).\(pathExtension)"
                newURL = parentUrl.appendingPathComponent(finalName)
            }
            do {
                if isFolder { try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false) }
                else { try "".write(to: newURL, atomically: true, encoding: .utf8) }
                return newURL
            } catch {
                print("Failed to create new item: \(error)"); return nil
            }
        }.value
    }

    func findItem(by url: URL, in item: FileItem? = nil) -> FileItem? {
        let currentItem = item ?? rootItem
        guard let currentItem = currentItem else { return nil }
        if currentItem.url == url { return currentItem }
        if let children = currentItem.children {
            for child in children {
                if let found = findItem(by: url, in: child) { return found }
            }
        }
        return nil
    }
    
    func selectFile(at url: URL) {
        if let item = findItem(by: url) {
            self.selectedItem = item; var parent = item.parent
            while let p = parent {
                if !p.isExpanded { toggleExpansion(for: p) }
                parent = p.parent
            }
        }
    }

    // MARK: - Bookmarking
    private func restoreWorkspace() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: UserDefaultsKeys.workspaceBookmark) else { return }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale { print("Workspace bookmark is stale.") }
            setWorkspace(url: url)
        } catch {
            print("Error restoring workspace from bookmark: \(error)")
        }
    }
    
    private func saveWorkspaceBookmark(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: UserDefaultsKeys.workspaceBookmark)
        } catch {
            print("Failed to save workspace bookmark: \(error)")
        }
    }
}

fileprivate class FileSystemMonitor {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.avante.fsmonitor")
    var changeHandler: (() -> Void)?
    func startMonitoring(path: String) {
        stopMonitoring()
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { (stream, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let info = clientCallBackInfo else { return }
            let mySelf = Unmanaged<FileSystemMonitor>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { mySelf.changeHandler?() }
        }
        stream = FSEventStreamCreate(nil, callback, &context, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }
    func stopMonitoring() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }
    deinit { stopMonitoring() }
}
