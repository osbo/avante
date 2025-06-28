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
                if workspace.isSingleFileMode {
                    singleFileView
                } else {
                    workspaceView
                }
            } else {
                WelcomeView(onOpenWorkspace: workspace.openFileOrFolder, onOpenFile: workspace.openFileOrFolder)
            }
        }
        .onAppear {
            analysisController.setWorkspace(workspace)
            analysisController.isFocusModeEnabled = isFocusModeEnabled
            if workspace.isSingleFileMode, let item = workspace.selectedFileForEditor {
                let documentToLoad = workspace.getDocument(for: item)
                analysisController.loadDocument(document: documentToLoad)
            }
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

    private var singleFileView: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let fileItem = workspace.selectedFileForEditor {
                    EditorTitleBar(fileItem: fileItem)
                }
                AIAnalysisTextView(
                    text: Binding(
                        get: { analysisController.documentText },
                        set: { analysisController.documentText = $0 }
                    ),
                    analysisController: analysisController
                )
                .id(workspace.selectedFileForEditor?.id)
                .onReceive(NotificationCenter.default.publisher(for: .saveAction)) { _ in
                    analysisController.saveDocument()
                }
                .onReceive(NotificationCenter.default.publisher(for: .reanalyzeAction)) { notification in
                    if let item = notification.object as? FileItem, item.id == workspace.selectedFileForEditor?.id {
                        analysisController.reanalyzeActiveDocument()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleHighlight)) { notification in
                    if let metricType = notification.object as? MetricType {
                        analysisController.toggleHighlight(for: metricType)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .clearHighlights)) { _ in
                    analysisController.activeHighlight = nil
                }
                .onReceive(NotificationCenter.default.publisher(for: .renameAction)) { notification in
                    if let selectedItem = notification.object as? FileItem {
                        NotificationCenter.default.post(name: .triggerRename, object: selectedItem)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if let fileItem = workspace.selectedFileForEditor {
                    print("🎨 singleFileView appeared with file: \(fileItem.name)")
                } else {
                    print("🎨 singleFileView appeared with no file")
                }
            }
            MetricsSidebar(analysisController: analysisController)
                .background(
                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                )
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 220, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var workspaceView: some View {
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
                VStack(spacing: 0) {
                    EditorTitleBar(fileItem: fileItem)
                    AIAnalysisTextView(
                        text: Binding(
                            get: { analysisController.documentText },
                            set: { analysisController.documentText = $0 }
                        ),
                        analysisController: analysisController
                    )
                    .id(fileItem.id)
                    .onReceive(NotificationCenter.default.publisher(for: .saveAction)) { _ in
                        analysisController.saveDocument()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .reanalyzeAction)) { notification in
                        if let item = notification.object as? FileItem, item.id == fileItem.id {
                            analysisController.reanalyzeActiveDocument()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .toggleHighlight)) { notification in
                        if let metricType = notification.object as? MetricType {
                            analysisController.toggleHighlight(for: metricType)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .clearHighlights)) { _ in
                        analysisController.activeHighlight = nil
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .renameAction)) { notification in
                        if let selectedItem = notification.object as? FileItem {
                            NotificationCenter.default.post(name: .triggerRename, object: selectedItem)
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)
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
        .ignoresSafeArea()
    }
}

// Helper view for the title bar with dirty dot
fileprivate struct EditorTitleBar: View {
    @ObservedObject var fileItem: FileItem
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            Text(fileItem.name.replacingOccurrences(of: ".vnt", with: ""))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            if fileItem.isDirty {
                Text(" – Edited")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

struct WelcomeView: View {
    var onOpenWorkspace: () -> Void
    var onOpenFile: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("Avante")
                .font(.system(size: 56, weight: .bold, design: .serif))
            
            Text("Select a workspace folder or a single file to begin your work.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onOpenWorkspace) {
                HStack {
                    Image(systemName: "folder")
                    Text("Open...")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
