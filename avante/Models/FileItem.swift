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
    let id: UUID = UUID()
    var url: URL
    weak var parent: FileItem?
    @Published var children: [FileItem]?
    @Published var isExpanded: Bool = false
    
    @Published var isDirty: Bool = false

    var isFolder: Bool {
        children != nil
    }

    var name: String {
        get { url.lastPathComponent }
        set {
            let newUrl = url.deletingLastPathComponent().appendingPathComponent(newValue)
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
            self.children = nil
            print("Warning: Could not determine if \(url.lastPathComponent) is a directory. Assuming file. Error: \(error)")
        }
    }
}

extension FileItem: Hashable {
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
