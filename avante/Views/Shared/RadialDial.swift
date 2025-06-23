//
//  RadialDial.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI

struct RadialDial: View {
    let metric: AnalysisMetricsGroup
    let type: MetricType
    let title: String
    
    private let startAngle = Angle(degrees: 135)
    private let endAngle = Angle(degrees: 45)
    
    private var value: Double {
        switch type {
        case .predictability: return metric.predictability
        case .clarity: return metric.clarity
        case .flow: return metric.flow
        }
    }
    
    var body: some View {
        VStack {
            ZStack {
                Path { path in
                    path.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                }
                .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .foregroundColor(.gray.opacity(0.3))
                
                Path { path in
                    let valueAngle = startAngle + (Angle(degrees: 270) * value)
                    path.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: startAngle, endAngle: valueAngle, clockwise: false)
                }
                .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .foregroundColor(Color.green)
                
                Text(String(format: "%.0f", value*100))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(width: 100, height: 100)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
        }
    }
}

extension Angle {
    static func + (lhs: Angle, rhs: Angle) -> Angle {
        return Angle(degrees: lhs.degrees + rhs.degrees)
    }
}
