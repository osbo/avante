//
//  EditView.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI

struct EditView: View {
    @Binding var document: AvanteDocument
    @State private var isShowingSheet = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack {
            TextEditor(text: $document.text)
                .font(.title)
                .textEditorStyle(.plain)
                .scrollIndicators(.never)
                .onAppear {
                    self.isFocused = true
                }
                .focused($isFocused)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
        .background(.gray)
        .scrollClipDisabled()
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .shadow(color: .black.opacity(0.2), radius: 5)
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    EditView(document: .constant(AvanteDocument()))
}
