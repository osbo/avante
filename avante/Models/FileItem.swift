//
//  FileItem.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import Foundation
import SwiftUI
import Combine

class FileItem: Identifiable, ObservableObject {
    let id: URL
    @Published var children: [FileItem]?
    @Published var isExpanded: Bool = false
    @Published var isRenaming: Bool = false

    var isFolder: Bool {
        children != nil
    }

    var name: String {
        id.lastPathComponent
    }

    init(url: URL, children: [FileItem]? = nil) {
        self.id = url
        if url.hasDirectoryPath {
            self.children = children ?? []
        } else {
            self.children = nil
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