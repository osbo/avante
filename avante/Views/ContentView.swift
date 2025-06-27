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
    @AppStorage("activeHighlight") private var activeHighlightRaw: String = ""
    @Binding var isFocusModeEnabled: Bool
    
    init(workspace: WorkspaceViewModel, isFocusModeEnabled: Binding<Bool>) {
        self.workspace = workspace
        self._isFocusModeEnabled = isFocusModeEnabled
    }

    var body: some View {
        Group {
            if workspace.rootItem != nil {
                NavigationSplitView {
                    VStack(spacing: 0) {
                        Text(workspace.rootItem?.name ?? "Avante")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture {
                                workspace.selectedItem = nil
                            }

                        ZStack {
                            // The background is now handled by the parent
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
                        .onReceive(NotificationCenter.default.publisher(for: .reanalyzeAction)) { notification in
                            if let item = notification.object as? FileItem, item.id == fileItem.id {
                                print("Re-analyze command received for \(item.name)")
                                analysisController.reanalyzeActiveDocument()
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .toggleHighlight)) { notification in
                            if let metricType = notification.object as? MetricType {
                                print("Toggle highlight command received for \(metricType.rawValue)")
                                analysisController.toggleHighlight(for: metricType)
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .clearHighlights)) { _ in
                            print("Clear highlights command received")
                            analysisController.activeHighlight = nil
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .renameAction)) { notification in
                            if let selectedItem = notification.object as? FileItem {
                                print("Rename command received for \(selectedItem.name)")
                                // Trigger rename by posting a notification that the file explorer will handle
                                NotificationCenter.default.post(name: .triggerRename, object: selectedItem)
                            }
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
                        .background(
                            RoundedRectangle(cornerRadius: 0, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea()
                        )
                        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
                }
                // FIX: Apply a single, consistent background to the entire split view.
                // .background(Color(nsColor: .textBackgroundColor))
                .ignoresSafeArea()
            } else {
                WelcomeView(onOpen: workspace.openFileOrFolder)
            }
        }
        .onAppear {
            analysisController.setWorkspace(workspace)
            analysisController.isFocusModeEnabled = isFocusModeEnabled
        }
        .onChange(of: workspace.selectedFileForEditor) { _, newFileItem in
            guard let item = newFileItem else {
                analysisController.loadDocument(document: nil)
                return
            }
            let documentToLoad = workspace.getDocument(for: item)
            analysisController.loadDocument(document: documentToLoad)
        }
        .onChange(of: activeHighlightRaw) { _, newValue in
            analysisController.activeHighlight = MetricType(rawValue: newValue)
        }
        .onChange(of: isFocusModeEnabled) { _, newValue in
            analysisController.isFocusModeEnabled = newValue
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
    }
}
