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
    @StateObject private var analysisController = AnalysisController()
    
    init(workspace: WorkspaceViewModel) {
        self.workspace = workspace
    }

    var body: some View {
        Group {
            if workspace.rootItem != nil {
                NavigationSplitView {
                    VStack(spacing: 0) {
                        Text(workspace.rootItem?.name ?? "AVANTE")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .onTapGesture {
                                workspace.selectedItem = nil
                            }

                        ZStack {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    workspace.selectedItem = nil
                                }
                            NativeFileExplorer(workspace: workspace)
                        }
                        
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
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250)
                } content: {
                    if let fileItem = workspace.selectedFileForEditor {
                        AIAnalysisTextView(
                            text: $analysisController.documentText,
                            analysisController: analysisController
                        )
                        .id(fileItem.id)
                        .onReceive(NotificationCenter.default.publisher(for: .saveAction)) { _ in
                            print("Save command received. Saving document.")
                            analysisController.saveDocument()
                        }
                    } else {
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
                    MetricsSidebar(analysisController: analysisController)
                        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
                }
                .ignoresSafeArea()
            } else {
                WelcomeView(onOpen: workspace.openFileOrFolder)
            }
        }
        .onAppear {
            analysisController.setWorkspace(workspace)
        }
        .onChange(of: workspace.selectedFileForEditor) { _, newFileItem in
            guard let item = newFileItem else {
                analysisController.loadDocument(document: nil)
                return
            }
            let documentToLoad = workspace.getDocument(for: item)
            analysisController.loadDocument(document: documentToLoad)
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
