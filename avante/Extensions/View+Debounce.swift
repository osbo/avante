//
//  View+Debounce.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI

struct DebounceModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let delay: Duration
    let action: (Value) -> Void
    
    @State private var task: Task<Void, Never>?
    
    func body(content: Content) -> some View {
        content
            .onChange(of: value) { oldValue, newValue in
                task?.cancel()
                task = Task {
                    do {
                        try await Task.sleep(for: delay)
                        await MainActor.run {
                            action(newValue)
                        }
                    } catch {
                        
                    }
                }
            }
    }
}

extension View {
    func onChangeDebounced<Value: Equatable>(
        of value: Value,
        for delay: Duration,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        self.modifier(DebounceModifier(value: value, delay: delay, action: action))
    }
}
