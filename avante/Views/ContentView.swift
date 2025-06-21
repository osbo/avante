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
    @ObservedObject private var workspace: WorkspaceViewModel
    @State private var analysisViewModel: AnalysisViewModel?

    init(workspace: WorkspaceViewModel) {
        self.workspace = workspace
    }

    var body: some View {
        Group {
            if let rootUrl = workspace.workspaceRootUrl {
                NavigationSplitView {
                    VStack(spacing: 0) {
                        NativeFileExplorer(workspace: workspace)
                        Divider()
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
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220)
                } content: {
                    if let fileUrl = workspace.selectedFileUrl, let vm = analysisViewModel {
                        EditView(viewModel: vm)
                            .id(fileUrl)
                    } else {
                        Text("Select a file")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                } detail: {
                    MetricsSidebar(viewModel: analysisViewModel)
                        .navigationSplitViewColumnWidth(min: 240, ideal: 260)
                }
                .ignoresSafeArea()
            } else {
                WelcomeView(onOpen: workspace.openFolder)
            }
        }
        .onChange(of: workspace.selectedFileUrl) { _, newUrl in
            if let url = newUrl {
                analysisViewModel = AnalysisViewModel(fileUrl: url)
            } else {
                analysisViewModel = nil
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
