//
//  NativeFileExplorer.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import AppKit

fileprivate class FileCellView: NSTableCellView {
    let nameTextField = NSTextField(labelWithString: "")
    let iconImageView = NSImageView()
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        iconImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        nameTextField.isBezeled = false
        nameTextField.drawsBackground = false
        nameTextField.isEditable = false
        nameTextField.cell?.truncatesLastVisibleLine = true
        nameTextField.lineBreakMode = .byTruncatingTail
        
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6
        
        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(nameTextField)
        addSubview(stackView)
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(for item: FileItem) {
        if item.isFolder {
            iconImageView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")
            iconImageView.contentTintColor = .secondaryLabelColor
            nameTextField.stringValue = item.name
        } else {
            iconImageView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: "Document")
            iconImageView.contentTintColor = .controlAccentColor
            nameTextField.stringValue = item.url.deletingPathExtension().lastPathComponent
        }
    }
    
    func beginEditing() {
        nameTextField.isEditable = true
        window?.makeFirstResponder(nameTextField)
        nameTextField.currentEditor()?.selectAll(nil)
    }
}

fileprivate class CustomOutlineView: NSOutlineView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0 && !self.isRowSelected(row) { self.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return super.menu(for: event)
    }
}

struct NativeFileExplorer: NSViewRepresentable {
    @ObservedObject var workspace: WorkspaceViewModel

    func makeNSView(context: Context) -> NSScrollView {
        // ... (This function remains the same)
        let scrollView = NSScrollView(); let outlineView = CustomOutlineView()
        outlineView.dataSource = context.coordinator; outlineView.delegate = context.coordinator
        outlineView.headerView = nil; outlineView.style = .sourceList; outlineView.floatsGroupRows = false; outlineView.rowHeight = 28
        let column = NSTableColumn(identifier: .init("column")); outlineView.addTableColumn(column); outlineView.outlineTableColumn = column
        outlineView.target = context.coordinator; outlineView.doubleAction = #selector(Coordinator.doubleClickAction)
        let menu = NSMenu(); menu.delegate = context.coordinator; outlineView.menu = menu
        scrollView.documentView = outlineView; scrollView.hasVerticalScroller = true; scrollView.borderType = .noBorder
        context.coordinator.outlineView = outlineView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView else { return }
        context.coordinator.workspace = workspace
        
        // FIX: The update logic is now much simpler and more robust.
        
        // 1. Check for a pending insertion event.
        if let insertion = workspace.pendingInsertion {
            // Immediately clear the flag to acknowledge the event.
            workspace.pendingInsertion = nil
            // Delegate the entire complex operation to the coordinator.
            context.coordinator.performInsertAndRename(for: insertion.item, in: insertion.parent, in: outlineView)
        } else {
            // 2. For all other updates, just reload and sync.
            outlineView.reloadData()
            context.coordinator.syncSelectionAndExpansion(in: outlineView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(workspace: workspace) }
    
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
        var workspace: WorkspaceViewModel
        weak var outlineView: NSOutlineView?
        private var itemBeingEdited: FileItem?

        init(workspace: WorkspaceViewModel) { self.workspace = workspace }
        
        // MARK: - Core UI Choreography
        
        // FIX: This new function handles the entire create-and-rename flow imperatively.
        func performInsertAndRename(for item: FileItem, in parent: FileItem, in outlineView: NSOutlineView) {
            // 1. Update the data model first.
            parent.children?.append(item)
            parent.children?.sort { ($0.isFolder && !$1.isFolder) || ($0.isFolder == $1.isFolder && $0.name.localizedStandardCompare($1.name) == .orderedAscending) }
            
            // 2. Find the item's new index in the sorted array.
            guard let insertionIndex = parent.children?.firstIndex(of: item) else { return }

            // 3. Animate the insertion in the UI.
            outlineView.insertItems(at: IndexSet(integer: insertionIndex), inParent: parent, withAnimation: .effectGap)
            
            // 4. Select the new row.
            let row = outlineView.row(forItem: item)
            guard row != -1 else { return }
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            
            // 5. Scroll to make it visible.
            outlineView.scrollRowToVisible(row)
            
            // 6. Finally, begin editing.
            beginEditing(item: item, in: outlineView)
        }

        func beginEditing(item: FileItem, in outlineView: NSOutlineView) {
            let row = outlineView.row(forItem: item)
            guard row != -1 else { return }
            if let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? FileCellView {
                cell.beginEditing()
            }
        }
        
        // MARK: - Data Source
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let fileItem = item as? FileItem else { return workspace.rootItem?.children?.count ?? 0 }
            return fileItem.children?.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let fileItem = item as? FileItem else { return workspace.rootItem!.children![index] }
            return fileItem.children![index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileItem)?.isFolder ?? false
        }
        
        // MARK: - Delegate
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let fileItem = item as? FileItem else { return nil }
            let id = NSUserInterfaceItemIdentifier("FileCell")
            let cellView = outlineView.makeView(withIdentifier: id, owner: self) as? FileCellView ?? FileCellView()
            cellView.identifier = id
            cellView.configure(for: fileItem)
            cellView.nameTextField.delegate = self
            return cellView
        }
        
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView,
                  // Prevent this from firing when we are programmatically setting selection
                  outlineView.window?.firstResponder == outlineView else { return }
            
            let selectedIndex = outlineView.selectedRow
            DispatchQueue.main.async {
                if selectedIndex != -1, let item = outlineView.item(atRow: selectedIndex) as? FileItem {
                    if self.workspace.selectedItem != item { self.workspace.selectedItem = item }
                } else {
                    if self.workspace.selectedItem != nil { self.workspace.selectedItem = nil }
                }
            }
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            if let item = notification.userInfo?["NSObject"] as? FileItem, !item.isExpanded { workspace.toggleExpansion(for: item) }
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            if let item = notification.userInfo?["NSObject"] as? FileItem, item.isExpanded { workspace.toggleExpansion(for: item) }
        }
        
        @objc func doubleClickAction(_ sender: Any?) {
            guard let outlineView = self.outlineView, let item = outlineView.item(atRow: outlineView.clickedRow) as? FileItem else { return }
            if item.isFolder { workspace.toggleExpansion(for: item) }
            else { workspace.selectedItem = item }
        }

        // MARK: - Renaming Logic
        func controlTextDidBeginEditing(_ obj: Notification) {
            // This function is now correctly protected by the viewState logic.
            guard let textField = obj.object as? NSTextField,
                  let cell = textField.superview?.superview as? FileCellView,
                  let outlineView = self.outlineView,
                  let item = outlineView.item(atRow: outlineView.row(for: cell)) as? FileItem else { return }
            self.itemBeingEdited = item
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            // This correctly resets the state machine to idle after ANY edit.
            guard let textField = obj.object as? NSTextField, let item = self.itemBeingEdited else {
                return
            }
            
            textField.isEditable = false
            let newBaseName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !newBaseName.isEmpty {
                let currentName = item.url.deletingPathExtension().lastPathComponent
                if newBaseName != currentName {
                    let ext = item.url.pathExtension
                    let finalName = ext.isEmpty ? newBaseName : "\(newBaseName).\(ext)"
                    workspace.renameItem(item, to: finalName)
                }
            } else {
                 outlineView?.reloadItem(item, reloadChildren: false)
            }
            self.itemBeingEdited = nil
        }
        
        // MARK: - Context Menu
        @objc func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outlineView = self.outlineView else { return }
            let clickedItem = outlineView.selectedRow >= 0 ? outlineView.item(atRow: outlineView.selectedRow) as? FileItem : nil
            var parentForNewItem: FileItem?
            if let clickedItem = clickedItem { parentForNewItem = clickedItem.isFolder ? clickedItem : clickedItem.parent }
            else { parentForNewItem = workspace.rootItem }

            let newFile = NSMenuItem(title: "New File", action: #selector(newFileAction), keyEquivalent: "")
            newFile.representedObject = parentForNewItem; newFile.target = self; menu.addItem(newFile)
            
            let newFolder = NSMenuItem(title: "New Folder", action: #selector(newFolderAction), keyEquivalent: "")
            newFolder.representedObject = parentForNewItem; newFolder.target = self; menu.addItem(newFolder)

            if let clickedItem = clickedItem {
                menu.addItem(.separator())
                let rename = NSMenuItem(title: "Rename", action: #selector(renameAction), keyEquivalent: "")
                rename.representedObject = clickedItem; rename.target = self; menu.addItem(rename)
                let delete = NSMenuItem(title: "Delete", action: #selector(deleteAction), keyEquivalent: "")
                delete.representedObject = clickedItem; delete.target = self; menu.addItem(delete)
            }
        }
        
        @objc func newFileAction(_ sender: Any?) { if let p = (sender as? NSMenuItem)?.representedObject as? FileItem { workspace.createNewFile(in: p) } }
        @objc func newFolderAction(_ sender: Any?) { if let p = (sender as? NSMenuItem)?.representedObject as? FileItem { workspace.createNewFolder(in: p) } }
        @objc func renameAction(_ sender: Any?) {
            if let item = (sender as? NSMenuItem)?.representedObject as? FileItem, let outlineView = self.outlineView {
                // We don't need a state machine anymore because the update logic is safer.
                beginEditing(item: item, in: outlineView)
            }
        }
        @objc func deleteAction(_ sender: Any?) { if let i = (sender as? NSMenuItem)?.representedObject as? FileItem { workspace.deleteItem(i) } }
        
        // MARK: - Sync Logic
        func syncSelectionAndExpansion(in outlineView: NSOutlineView) {
            func expand(items: [FileItem]) {
                for item in items {
                    if item.isExpanded {
                        outlineView.expandItem(item, expandChildren: false)
                        if let children = item.children { expand(items: children) }
                    }
                }
            }
            if let rootChildren = workspace.rootItem?.children { expand(items: rootChildren) }
            
            if let selectedItem = workspace.selectedItem {
                let row = outlineView.row(forItem: selectedItem)
                if row != -1 && !outlineView.isRowSelected(row) {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outlineView.scrollRowToVisible(row)
                }
            } else {
                outlineView.deselectAll(nil)
            }
        }
    }
}
