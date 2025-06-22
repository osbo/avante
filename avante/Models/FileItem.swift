//
//  FileItem.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class FileItem: Identifiable, ObservableObject {
    // Use a stable UUID for Identifiable conformance. The URL can change when renaming.
    let id: UUID = UUID()
    var url: URL // The URL is now a mutable property.
    weak var parent: FileItem?
    @Published var children: [FileItem]?
    @Published var isExpanded: Bool = false
    @Published var isRenaming: Bool = false // This can be removed, as the coordinator will handle it.

    var isFolder: Bool {
        children != nil
    }

    var name: String {
        get { url.lastPathComponent }
        set {
            let newUrl = url.deletingLastPathComponent().appendingPathComponent(newValue)
            // This is a placeholder; actual renaming is handled in the ViewModel.
            url = newUrl
        }
    }

    init(url: URL, children: [FileItem]? = nil) {
        self.url = url
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                self.children = children ?? []
            } else {
                self.children = nil
            }
        } catch {
            // If we can't get resource values, assume it's a file.
            self.children = nil
            print("Warning: Could not determine if \(url.lastPathComponent) is a directory. Assuming file. Error: \(error)")
        }
    }
}

extension FileItem: Hashable {
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        // Identity is based on the stable UUID.
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        // Identity is based on the stable UUID.
        hasher.combine(id)
    }
}
