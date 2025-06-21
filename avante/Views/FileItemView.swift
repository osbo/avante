//
//  FileItemView.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import Combine

struct FileItemView: View {
    @ObservedObject var item: FileItem
    var onCommit: (String) -> Void
    
    @State private var newName: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isFolder ? "folder" : "doc.text")
                .foregroundColor(item.isFolder ? .accentColor : .secondary)
                .frame(width: 16)

            if item.isRenaming {
                TextField("New Name", text: $newName, onCommit: {
                    onCommit(newName)
                    item.isRenaming = false
                })
                .focused($isFocused)
                .onAppear {
                    self.newName = item.name
                    // A slight delay ensures the text field is in the view hierarchy before focusing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isFocused = true
                    }
                }
            } else {
                Text(item.name)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
} 
