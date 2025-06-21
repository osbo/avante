//
//  NativeFileExplorer.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import AppKit

fileprivate class FileExplorerHostingView: NSHostingView<FileItemView> {
    weak var outlineView: NSOutlineView?
    var row: Int = -1
    
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let coordinator = self.outlineView?.delegate as? NativeFileExplorer.Coordinator else {
            return super.menu(for: event)
        }
        return coordinator.menu(forRow: self.row)
    }
}

fileprivate class CustomOutlineView: NSOutlineView {
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        // Check for Return (36) or Enter on the numpad (76)
        if event.keyCode == 36 || event.keyCode == 76 {
            if selectedRow != -1 {
                // If a row is selected, perform the double-click action.
                // The target/action is set up in makeNSView.
                if let target = self.target, let action = self.doubleAction {
                    target.perform(action, with: self)
                }
                // We've handled the event, so we return to prevent the "donk" sound.
                return
            }
        }
        
        // For all other keys (like arrows), use the default AppKit behavior.
        super.keyDown(with: event)
    }
}

struct NativeFileExplorer: NSViewRepresentable {
    @ObservedObject var workspace: WorkspaceViewModel

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let outlineView = CustomOutlineView()
        
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(context.coordinator.doubleClickAction)
        
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        context.coordinator.outlineView = outlineView
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.workspace = workspace
        
        guard let outlineView = nsView.documentView as? NSOutlineView else { return }

        // Only reload data if the fileTree has actually been replaced
        if context.coordinator.lastFileTreeObjectID != ObjectIdentifier(workspace.fileTree as AnyObject) {
            outlineView.reloadData()
            context.coordinator.lastFileTreeObjectID = ObjectIdentifier(workspace.fileTree as AnyObject)
        }

        // Restore expansion state
        context.coordinator.expandItems(in: outlineView)
        
        // Restore selection
        if let selectedItem = context.coordinator.workspace.selectedItem,
           let row = context.coordinator.row(forItem: selectedItem, in: outlineView) {
            context.coordinator.isProgrammaticSelection = true
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            context.coordinator.isProgrammaticSelection = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(workspace: workspace)
    }

    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var workspace: WorkspaceViewModel
        var outlineView: NSOutlineView?
        var isProgrammaticSelection = false
        var lastFileTreeObjectID: ObjectIdentifier?

        init(workspace: WorkspaceViewModel) {
            self.workspace = workspace
        }
        
        // Find the row for a given URL (recursively) - this is a simplified stub
        func row(forItem item: FileItem, in outlineView: NSOutlineView) -> Int? {
            // A full implementation requires mapping the tree to flat rows.
            // For this specific use case, we can use the outline view's own method.
            let row = outlineView.row(forItem: item)
            return row == -1 ? nil : row
        }

        func expandItems(in outlineView: NSOutlineView, for items: [FileItem]? = nil) {
            let itemsToScan = items ?? workspace.fileTree
            for item in itemsToScan {
                if item.isExpanded {
                    outlineView.expandItem(item)
                    if let children = item.children {
                        expandItems(in: outlineView, for: children)
                    }
                }
            }
        }
        
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if let fileItem = item as? FileItem {
                return fileItem.children?.count ?? 0
            }
            return workspace.fileTree.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if let fileItem = item as? FileItem {
                return fileItem.children![index]
            }
            return workspace.fileTree[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileItem)?.isFolder ?? false
        }
        
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let fileItem = item as? FileItem else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("FileItemCell")
            let view: FileExplorerHostingView
            
            if let recycledView = outlineView.makeView(withIdentifier: identifier, owner: self) as? FileExplorerHostingView {
                view = recycledView
                view.rootView = FileItemView(item: fileItem) { newName in
                    self.workspace.renameItem(fileItem, to: newName)
                }
            } else {
                view = FileExplorerHostingView(rootView:
                    FileItemView(item: fileItem) { newName in
                        self.workspace.renameItem(fileItem, to: newName)
                    }
                )
                view.identifier = identifier
            }

            view.sizingOptions = .intrinsicContentSize
            view.outlineView = outlineView
            view.row = outlineView.row(forItem: item)
            
            return view
        }
        
        func outlineViewItemWillExpand(_ notification: Notification) {
            if let fileItem = notification.userInfo?["NSObject"] as? FileItem {
                workspace.loadChildren(for: fileItem)
                workspace.expandedItemIDs.insert(fileItem.id)
                fileItem.isExpanded = true
            }
        }
        
        func outlineViewItemDidExpand(_ notification: Notification) {
            // Select the item that was just expanded
            if let fileItem = notification.userInfo?["NSObject"] as? FileItem, let outlineView = self.outlineView {
                let row = outlineView.row(forItem: fileItem)
                if row != -1 {
                    isProgrammaticSelection = true
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    // Manually update the view model's selection since this is programmatic
                    workspace.selectedItem = fileItem
                    isProgrammaticSelection = false
                }
            }
        }
        
        func outlineViewItemDidCollapse(_ notification: Notification) {
            if let fileItem = notification.userInfo?["NSObject"] as? FileItem {
                workspace.expandedItemIDs.remove(fileItem.id)
                fileItem.isExpanded = false

                // Select the item that was just collapsed
                if let outlineView = self.outlineView {
                    let row = outlineView.row(forItem: fileItem)
                    if row != -1 {
                        isProgrammaticSelection = true
                        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                        workspace.selectedItem = fileItem
                        isProgrammaticSelection = false
                    }
                }
            }
        }
        
        func outlineViewSelectionDidChange(_ notification: Notification) {
            if isProgrammaticSelection { return }

            guard let outlineView = notification.object as? NSOutlineView else { return }
            
            let selectedIndex = outlineView.selectedRow
            if selectedIndex != -1, let item = outlineView.item(atRow: selectedIndex) as? FileItem {
                workspace.selectedItem = item
            } else {
                workspace.selectedItem = nil
            }
        }
        
        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            return 28
        }
        
        func menu(forRow row: Int) -> NSMenu? {
            // Select the row that was right-clicked, if it's not already selected.
            if row >= 0, let outlineView = self.outlineView, outlineView.selectedRow != row {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }

            let menu = NSMenu()
            
            let item = row >= 0 ? outlineView?.item(atRow: row) as? FileItem : nil
            
            let newFileItem = NSMenuItem(title: "New File", action: #selector(newFileAction(_:)), keyEquivalent: "")
            newFileItem.representedObject = item
            newFileItem.target = self
            menu.addItem(newFileItem)
            
            let newFolderItem = NSMenuItem(title: "New Folder", action: #selector(newFolderAction(_:)), keyEquivalent: "")
            newFolderItem.representedObject = item
            newFolderItem.target = self
            menu.addItem(newFolderItem)
            
            if item != nil {
                menu.addItem(.separator())
                
                let renameItem = NSMenuItem(title: "Rename", action: #selector(renameAction(_:)), keyEquivalent: "")
                renameItem.representedObject = item
                renameItem.target = self
                menu.addItem(renameItem)

                let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteAction(_:)), keyEquivalent: "")
                deleteItem.representedObject = item
                deleteItem.target = self
                menu.addItem(deleteItem)
            }
            
            return menu
        }

        @objc func newFileAction(_ sender: NSMenuItem) {
            let item = sender.representedObject as? FileItem
            workspace.createNewFile(in: item)
        }

        @objc func newFolderAction(_ sender: NSMenuItem) {
            let item = sender.representedObject as? FileItem
            workspace.createNewFolder(in: item)
        }
        
        @objc func renameAction(_ sender: NSMenuItem) {
            if let item = sender.representedObject as? FileItem {
                item.isRenaming = true
            }
        }
        
        @objc func deleteAction(_ sender: NSMenuItem) {
            if let item = sender.representedObject as? FileItem {
                // You might want to show a confirmation alert here
                workspace.deleteItem(item)
            }
        }
        
        @objc func doubleClickAction(_ sender: Any?) {
            guard let outlineView = sender as? NSOutlineView,
                  outlineView.selectedRow >= 0 else { return }
            
            let item = outlineView.item(atRow: outlineView.selectedRow)
            
            if let fileItem = item as? FileItem {
                if fileItem.isFolder {
                    if outlineView.isItemExpanded(fileItem) {
                        outlineView.collapseItem(fileItem)
                    } else {
                        workspace.loadChildren(for: fileItem)
                        outlineView.expandItem(fileItem)
                    }
                } else {
                    workspace.selectedFileUrl = fileItem.id
                }
            }
        }
    }
} 
