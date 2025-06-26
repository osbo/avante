//
//  SharedTypes.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import Foundation

enum MetricType: String, Codable, Equatable {
    case novelty
    case clarity
    case flow
    
    static let preferredOrder: [MetricType] = [.clarity, .flow, .novelty]
} 