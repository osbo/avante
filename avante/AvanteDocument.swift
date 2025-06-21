//
//  AvanteDocument.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import Combine

struct AvanteFile: Codable, Equatable {
    var text: String
    var analysis: [AnalysisMetric]
}

struct AnalysisMetric: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var chunk: String
    var value: Double
    var type: MetricType
}

class AvanteDocument: ObservableObject {
    @Published var file: AvanteFile
    
    private let url: URL
    
    init(url: URL) {
        self.url = url
        
        do {
            let data = try Data(contentsOf: url)
            self.file = try JSONDecoder().decode(AvanteFile.self, from: data)
            print("Successfully loaded file from \(url.lastPathComponent)")
        } catch {
            print("Could not load file, creating a new one. Error: \(error)")
            self.file = AvanteFile(text: "", analysis: [])
        }
    }
    
    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting =  .prettyPrinted
            let data = try encoder.encode(file)
            try data.write(to: url, options: .atomic)
            print("File saved successfully to \(url.lastPathComponent)")
        } catch {
            print("Failed to save file. Error : \(error)")
        }
    }
}
