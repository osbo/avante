//
//  View+Debounce.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import Combine

extension View {
    func debounce<Value: Equatable>(
        _ value: Binding<Value>,
        for dueTime: TimeInterval
    ) -> some View {
        let subject = CurrentValueSubject<Value, Never>(value.wrappedValue)
        let publisher = subject
            .debounce(for: .seconds(dueTime), scheduler: RunLoop.main)
            .removeDuplicates()

        return self
            .onAppear {
                subject.send(value.wrappedValue)
            }
            .onChange(of: value.wrappedValue) { oldValue, newValue in
                subject.send(newValue)
            }
            .onReceive(publisher) { newValue in
                value.wrappedValue = newValue
            }
    }
}
