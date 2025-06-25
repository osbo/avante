//
//  MetricsSidebar.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI

struct MetricsSidebar: View {
    @ObservedObject var analysisController: AnalysisController
    
    var body: some View {
        VStack(spacing: 30) {
            let status = analysisController.status
            
            if status.contains("Priming") {
                ProgressView()
                    .padding(.bottom, 8)
                Text(status)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if let latestMetrics = analysisController.latestMetrics {
                dial(for: .novelty, metric: latestMetrics)
                dial(for: .clarity, metric: latestMetrics)
                dial(for: .flow, metric: latestMetrics)
                
                Spacer()
                
                if status == "Analyzing..." || status == "Word queued..." {
                    ProgressView()
                    Text(status)
                       .foregroundStyle(.secondary)
                       .padding(.bottom)
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
    
    @ViewBuilder
    private func dial(for type: MetricType, metric: AnalysisMetricsGroup) -> some View {
        let isActive = analysisController.activeHighlight == type
        
        VStack {
            RadialDial(metric: metric, type: type, title: type.rawValue.capitalized)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(isActive ? Color.accentColor.opacity(0.3) : Color.clear)
        .cornerRadius(12)
        // FIX: Make the entire rectangular area tappable.
        .contentShape(Rectangle())
        .onTapGesture {
            analysisController.toggleHighlight(for: type)
        }
    }
}

enum MetricType: String, Codable, Equatable {
    case novelty
    case clarity
    case flow
}
