//
//  MetricsSidebar.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI

struct MetricsSidebar: View {
    let viewModel: AnalysisViewModel?
    @State private var highlightedMetricType: MetricType?
    
    var body: some View {
        VStack(spacing: 30) {
            if let viewModel = viewModel,
               !viewModel.document.file.analysis.isEmpty {
                if let predictability = viewModel.document.file.analysis.first(where: { $0.type == MetricType.predictability }) {
                    RadialDial(metric: predictability, title: "Predictability")
                        .onHover { isHovering in
                            highlightedMetricType = isHovering ? .predictability : nil
                        }
                }
                
                if let clarity = viewModel.document.file.analysis.first(where: { $0.type == .clarity }) {
                    RadialDial(metric: clarity, title: "Clarity")
                        .onHover { isHovering in
                            highlightedMetricType = isHovering ? .clarity : nil
                        }
                }
                
                if let flow = viewModel.document.file.analysis.first(where: { $0.type == .flow }) {
                    RadialDial(metric: flow, title: "Flow")
                        .onHover { isHovering in
                            highlightedMetricType = isHovering ? .flow : nil
                        }
                }
            } else {
                Text("No analysis data.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: highlightedMetricType) { _, newValue in
            print("Hovering over: \(newValue?.rawValue ?? "none")")
        }
    }
}

enum MetricType: String, Codable, Equatable {
    case predictability
    case clarity
    case flow
}
