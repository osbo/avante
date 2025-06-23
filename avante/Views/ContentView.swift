//
//  ContentView.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @ObservedObject var workspace: WorkspaceViewModel

    init(workspace: WorkspaceViewModel) {
        self.workspace = workspace
    }

    var body: some View {
        Group {
            if workspace.rootItem != nil {
                NavigationSplitView {
                    VStack(spacing: 0) {
                        // MARK: - Sidebar Header
                        Text(workspace.rootItem?.name ?? "AVANTE")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .onTapGesture {
                                // Deselect by clicking the header
                                workspace.selectedItem = nil
                            }

                        // MARK: - File Explorer
                        // Using a ZStack with a clear color allows deselecting by clicking empty space
                        ZStack {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    workspace.selectedItem = nil
                                }
                            NativeFileExplorer(workspace: workspace)
                        }
                        
                        Divider()

                        // MARK: - Sidebar Footer Buttons
                        HStack(spacing: 20) {
                            Spacer()
                            Button(action: { workspace.createNewFile(in: workspace.selectedItem) }) {
                                Image(systemName: "doc.badge.plus")
                            }
                            Button(action: { workspace.createNewFolder(in: workspace.selectedItem) }) {
                                Image(systemName: "folder.badge.plus")
                            }
                            Spacer()
                        }
                        .padding(10)
                        .buttonStyle(.plain)
                        .labelStyle(.iconOnly)
                    }
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250)
                } content: {
                    // MARK: - Editor View Pane
                    // This now correctly observes the 'selectedFileForEditor' property from the ViewModel.
                    if let fileItem = workspace.selectedFileForEditor {
                        EditView(viewModel: workspace.viewModel(for: fileItem))
                            .id(fileItem.id)
                    } else {
                        // Placeholder view when no file is selected
                        VStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundStyle(.tertiary)
                            Text("Select a file to edit")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } detail: {
                    // MARK: - Metrics Sidebar
                    if let fileItem = workspace.selectedFileForEditor {
                        MetricsSidebar(viewModel: workspace.viewModel(for: fileItem))
                            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
                    } else {
                        // Placeholder when no file is selected for analysis
                        VStack {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 60))
                                .foregroundStyle(.tertiary)
                            Text("Select a file to see analysis")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
                    }
                }
                .ignoresSafeArea()
            } else {
                // MARK: - Welcome View
                WelcomeView(onOpen: workspace.openFileOrFolder)
            }
        }
    }
}

struct WelcomeView: View {
    var onOpen: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("Avante")
                .font(.system(size: 56, weight: .bold, design: .serif))
            
            Text("Select a file or folder to begin your work.")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Button(action: onOpen) {
                Text("Open File or Folder")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.green.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
