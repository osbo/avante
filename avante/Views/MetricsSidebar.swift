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
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                dial(for: .clarity)
                dial(for: .flow)
                dial(for: .novelty)
            }
            
            Spacer()

            StatusView(status: analysisController.status)
                .padding(.bottom, 20)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func dial(for type: MetricType) -> some View {
        let isActive = analysisController.activeHighlight == type
        ZStack {
            // Always render the highlight, but hide it when inactive
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: NSColor.unemphasizedSelectedContentBackgroundColor))
                .frame(width: 140, height: 130)
                .offset(y: -5)
                .opacity(isActive ? 1 : 0)
            RadialDial(
                metric: analysisController.metricsForDisplay,
                type: type
            )
            .frame(width: 100, height: 100)
        }
        .padding(.top, 18)
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
        .onTapGesture {
            analysisController.toggleHighlight(for: type)
        }
    }
}

private struct StatusView: View {
    let status: String
    
    var body: some View {
        let showProgress = status.contains("Priming") || status == "Analyzing..." || status == "Word queued..."
        
        HStack(spacing: 8) {
            if showProgress {
                ProgressView()
                    .controlSize(.small)
            }
            Text(status)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}


enum MetricType: String, Codable, Equatable {
    case novelty
    case clarity
    case flow
}

private struct RadialDial: View {
    let metric: AnalysisMetricsGroup?
    let type: MetricType
    
    private var title: String { type.rawValue.capitalized }
    
    private var value: Double {
        guard let metric = metric else { return 0 }
        switch type {
        case .novelty: return metric.novelty
        case .clarity: return metric.clarity
        case .flow: return metric.flow
        }
    }
    
    private func colorForDial(value: Double) -> Color {
        let hue = value * (120.0 / 360.0)
        return Color(hue: hue, saturation: 0.85, brightness: 0.9, opacity: 1.0)
    }
    
    @State private var animatedValue: Double = 0
    
    var body: some View {
        ZStack {
            // Background arc (full 270°)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Foreground (colored) arc, animated
            Circle()
                .trim(from: 0, to: 0.75 * animatedValue)
                .stroke(
                    metric != nil ? colorForDial(value: animatedValue) : Color.primary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .shadow(
                    color: metric != nil ? colorForDial(value: animatedValue).opacity(0.65) : .clear,
                    radius: 2,
                    x: 0,
                    y: 0
                )
                .rotationEffect(.degrees(135))
                .animation(.easeInOut(duration: 0.4), value: animatedValue)
            
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(width: 100, height: 100)
        .onAppear { animatedValue = value }
        .onChange(of: value) { newValue in
            withAnimation(.easeInOut(duration: 0.4)) {
                animatedValue = newValue
            }
        }
    }
}
