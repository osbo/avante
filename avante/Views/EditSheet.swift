//
//  EditSheet.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI

struct EditSheet: View {
    var text: String
    @Binding var isShowingSheet: Bool
    
    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Spacer()
                    DismissButton(isShowingSheet: $isShowingSheet)
                        .buttonStyle(.borderless)
                        .padding()
                }
                ScrollView {
                    VStack {
                        Text(text)
                            .font(.system(.body, design: .serif, weight: .regular))
                            .foregroundStyle(Color.brandDarkBlue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 50)
                }
            }
        }
    }
}

struct DismissButton: View {
    @Binding var isShowingSheet: Bool
    
    var body: some View {
        Button {
            isShowingSheet.toggle()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 20, height: 20)
                .foregroundColor(Color.brandLightBlue)
                .background(Color.brandDarkBlue)
                .cornerRadius(26)
        }
    }
}

#Preview {
    EditSheet(text: "", isShowingSheet: .constant(true))
}
