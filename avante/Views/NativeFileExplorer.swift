//
//  NativeFileExplorer.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import AppKit

// FileCellView definition remains unchanged
fileprivate class FileCellView: NSTableCellView {
    let nameTextField = NSTextField(labelWithString: "")
    let iconImageView = NSImageView()
    let dirtyIndicator = NSTextField(labelWithString: "•")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        iconImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        
        nameTextField.isBezeled = false
        nameTextField.drawsBackground = false
        nameTextField.isEditable = false
        nameTextField.cell?.truncatesLastVisibleLine = true
        nameTextField.lineBreakMode = .byTruncatingTail

        dirtyIndicator.isBezeled = false
        dirtyIndicator.drawsBackground = false
        dirtyIndicator.isEditable = false
        dirtyIndicator.font = .systemFont(ofSize: 20)
        
        [iconImageView, nameTextField, dirtyIndicator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameTextField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 6),
            nameTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
            dirtyIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            dirtyIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameTextField.trailingAnchor.constraint(lessThanOrEqualTo: dirtyIndicator.leadingAnchor, constant: -4)
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
        
        dirtyIndicator.isHidden = !item.isDirty
        dirtyIndicator.textColor = .labelColor
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
        let scrollView = NSScrollView(); let outlineView = CustomOutlineView()
        
        outlineView.dataSource = context.coordinator; outlineView.delegate = context.coordinator
        outlineView.headerView = nil; outlineView.style = .sourceList; outlineView.floatsGroupRows = false; outlineView.rowHeight = 28
        
        let column = NSTableColumn(identifier: .init("column")); outlineView.addTableColumn(column); outlineView.outlineTableColumn = column
        
        outlineView.target = context.coordinator; outlineView.doubleAction = #selector(Coordinator.doubleClickAction)
        
        let menu = NSMenu(); menu.delegate = context.coordinator; outlineView.menu = menu
        
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        
        // FIX: Ensure the scroll bar is only shown when scrolling.
        scrollView.autohidesScrollers = true
        
        context.coordinator.outlineView = outlineView
        return scrollView
    }
    
    // ... rest of NativeFileExplorer remains unchanged ...
    func makeCoordinator() -> Coordinator {
        return Coordinator(workspace: workspace)
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView else { return }
        context.coordinator.workspace = workspace
        
        outlineView.reloadData()
        context.coordinator.syncSelectionAndExpansion(in: outlineView)
    }
    
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
        var workspace: WorkspaceViewModel
        fileprivate var outlineView: CustomOutlineView?
        private var itemBeingEdited: FileItem?

        init(workspace: WorkspaceViewModel) { self.workspace = workspace }
        
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

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField,
                  let cell = textField.superview as? FileCellView,
                  let outlineView = self.outlineView,
                  let item = outlineView.item(atRow: outlineView.row(for: cell)) as? FileItem else { return }
            self.itemBeingEdited = item
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
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
            guard let item = (sender as? NSMenuItem)?.representedObject as? FileItem,
                  let outlineView = self.outlineView else { return }
            DispatchQueue.main.async {
                let row = outlineView.row(forItem: item)
                guard row != -1, let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileCellView else {
                    return
                }
                cell.beginEditing()
            }
        }
        @objc func deleteAction(_ sender: Any?) { if let i = (sender as? NSMenuItem)?.representedObject as? FileItem { workspace.deleteItem(i) } }
        
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
