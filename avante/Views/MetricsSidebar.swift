//
//  MetricsSidebar.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI

struct MetricsSidebar: View {
    @ObservedObject var viewModel: AnalysisViewModel
    @State private var highlightedMetricType: MetricType?
    
    private func aggregateMetric(for keyPath: KeyPath<AnalysisMetricsGroup, Double>, type: MetricType) -> AnalysisMetricsGroup? {
        let groups = viewModel.document.file.analysis
        guard !groups.isEmpty else { return nil }
        let total = groups.reduce(0.0) { $0 + $1[keyPath: keyPath] }
        let avg = total / Double(groups.count)
        // Only the relevant metric is set, others are zeroed for display
        return AnalysisMetricsGroup(
            range: CodableRange(lowerBound: 0, upperBound: 0),
            predictability: type == .predictability ? avg : 0,
            clarity: type == .clarity ? avg : 0,
            flow: type == .flow ? avg : 0
        )
    }
        
    
    var body: some View {
        VStack(spacing: 30) {
            let hasAnalysis = !viewModel.document.file.analysis.isEmpty
            let error = viewModel.analysisError

            if hasAnalysis {
                // Show the most recent analysis group (by highest range.upperBound)
                let latest = viewModel.document.file.analysis.max(by: { $0.range.upperBound < $1.range.upperBound })
                if let latest = latest {
                    RadialDial(metric: latest, type: .predictability, title: "Predictability")
                    RadialDial(metric: latest, type: .clarity, title: "Clarity")
                    RadialDial(metric: latest, type: .flow, title: "Flow")
                }
                Spacer()
            } else if let error = error {
                // Only show error if no analysis exists
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
            
                if viewModel.isAnalyzing {
                    ProgressView()
                    Text("Analyzing...")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Start writing to see analysis.")
                        .foregroundStyle(.secondary)
                }
            } else {
                if viewModel.isAnalyzing {
                    ProgressView()
                    Text("Analyzing...")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Start writing to see analysis.")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum MetricType: String, Codable, Equatable {
    case predictability
    case clarity
    case flow
}
