//
//  MetricsSidebar.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI

struct MetricsSidebar: View {
    @ObservedObject var analysisController: AnalysisController
    @State private var highlightedMetricType: MetricType?
    
    var body: some View {
        VStack(spacing: 30) {
            let hasAnalysis = analysisController.latestMetrics != nil
            let status = analysisController.status
            
            if status.contains("Priming") || status.contains("Initializing") {
                ProgressView()
                    .padding(.bottom, 8)
                Text(status)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if let latestMetrics = analysisController.latestMetrics {
                RadialDial(metric: latestMetrics, type: .predictability, title: "Predictability")
                RadialDial(metric: latestMetrics, type: .clarity, title: "Clarity")
                RadialDial(metric: latestMetrics, type: .flow, title: "Flow")
                Spacer()
                
                if status == "Analyzing..." {
                    ProgressView()
                    Text(status)
                       .foregroundStyle(.secondary)
                }
                
            } else {
                 VStack {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 60))
                        .foregroundStyle(.tertiary)
                    Text(status)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 30)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum MetricType: String, Codable, Equatable {
    case predictability
    case clarity
    case flow
}
