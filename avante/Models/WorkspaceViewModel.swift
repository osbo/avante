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
    
    private var documentCache: [URL: AvanteDocument] = [:]
    
    // FIX: This flag is now public so the AnalysisController can set it during saves.
    var isPerformingManualFileOperation = false
    
    private enum UserDefaultsKeys {
        static let workspaceBookmark = "workspaceBookmark"
    }
    
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
            self.refreshFileTree()
        }
    }

    func getDocument(for fileItem: FileItem) -> AvanteDocument {
        if let cachedDoc = documentCache[fileItem.url] {
            print("Document for '\(fileItem.name)' found in cache.")
            return cachedDoc
        } else {
            print("Loading document for '\(fileItem.name)' from disk.")
            let newDoc = AvanteDocument(url: fileItem.url)
            documentCache[fileItem.url] = newDoc
            return newDoc
        }
    }
    
    func markDocumentAsDirty(url: URL) {
        if let item = findItem(by: url) {
            if !item.isDirty {
                item.isDirty = true
                print("'\(item.name)' marked as dirty.")
                objectWillChange.send()
            }
        }
    }

    func markDocumentAsClean(url: URL) {
        if let item = findItem(by: url) {
            if item.isDirty {
                item.isDirty = false
                print("'\(item.name)' marked as clean.")
                objectWillChange.send()
            }
        }
    }
    
    func refreshFileTree() {
        print("Refreshing file tree...")
        guard let root = rootItem else { return }
        
        // Preserve the selection and expansion state before rebuilding the tree.
        let oldSelectionURL = selectedItem?.url
        let expandedURLs = self.expandedItemURLs
        
        // Preserve the dirty state of all open files.
        var dirtyStates: [URL: Bool] = [:]
        for (url, _) in documentCache {
            if let item = findItem(by: url), item.isDirty {
                dirtyStates[url] = true
            }
        }
        
        // Rebuild the file tree from scratch.
        root.children = buildFileTree(from: root.url, parent: root)
        
        // Re-apply the preserved state to the new items.
        self.expandedItemURLs = expandedURLs
        if let oldURL = oldSelectionURL { selectFile(at: oldURL) }
        dirtyStates.keys.forEach { markDocumentAsDirty(url: $0) }

        objectWillChange.send()
    }
    
    // ... other methods like openFileOrFolder, create, rename, delete, etc. remain the same ...
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
                self.selectedItem = newItem
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

                if let doc = documentCache.removeValue(forKey: oldURL) {
                    doc.updateURL(to: newURL)
                    documentCache[newURL] = doc
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
                documentCache.removeValue(forKey: urlToDelete)
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
    private func setWorkspace(url: URL) {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else {
            return
        }
        self.securityScopedURL = url
        saveWorkspaceBookmark(url)
        self.rootItem = FileItem(url: url)
        self.rootItem?.isExpanded = true
        refreshFileTree()
        fileSystemMonitor.startMonitoring(path: url.path)
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
    
    private func determineParent(for item: FileItem?) -> FileItem {
        guard let item = item else { return rootItem! }
        return item.isFolder ? item : item.parent ?? rootItem!
    }
    
    private func createUniqueItem(in parent: FileItem, baseName: String, isFolder: Bool) async -> URL? {
        let parentUrl = parent.url
        let pathExtension = isFolder ? "" : "vnt"
        
        let dataToSave: Data?
        if !isFolder {
            do {
                let emptyState = DocumentState(fullText: "", analysisSessions: [])
                dataToSave = try JSONEncoder().encode(emptyState)
            } catch {
                print("Failed to encode new item state: \(error)"); return nil
            }
        } else {
            dataToSave = nil
        }
        
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
                if isFolder {
                    try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
                } else if let data = dataToSave {
                    try data.write(to: newURL, options: .atomic)
                }
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
