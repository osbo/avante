//
//  EditView.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI

struct EditView: View {
    @ObservedObject var viewModel: AnalysisViewModel
    
    var body: some View {
        TextEditor(text: $viewModel.document.file.text)
            .font(.system(.body, design:.serif))
            .lineSpacing(8)
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollClipDisabled()
            .onChange(of: viewModel.document.file.text) { oldValue, newValue in
                viewModel.textDidChange(with: newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveAction)) { _ in
                print("Save command received. Saving document.")
                viewModel.document.save()
            }
    }
}
