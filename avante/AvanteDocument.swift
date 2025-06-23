//
//  AvanteDocument.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import Combine

struct CodableRange: Codable, Equatable, Hashable {
    let lowerBound: Int
    let upperBound: Int
}

struct AnalysisMetricsGroup: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    var range: CodableRange
    var predictability: Double
    var clarity: Double
    var flow: Double
}

struct AvanteFile: Codable, Equatable {
    var text: String
    var analysis: [AnalysisMetricsGroup]
}

class AvanteDocument: ObservableObject {
    @Published var file: AvanteFile
    private(set) var url: URL
    
    init(url: URL) {
        self.url = url
        
        // Check if file exists first
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        
        if fileExists {
            do {
                let data = try Data(contentsOf: url)
                
                // Validate that we have actual data
                guard !data.isEmpty else {
                    print("File exists but is empty, creating new document")
                    self.file = AvanteFile(text: "", analysis: [])
                    return
                }
                
                // Try to decode the JSON
                do {
                    self.file = try JSONDecoder().decode(AvanteFile.self, from: data)
                    print("Successfully loaded file from \(url.lastPathComponent)")
                } catch let decodingError as DecodingError {
                    print("JSON decoding failed for \(url.lastPathComponent): \(decodingError)")
                    // Create a new document if JSON is corrupted
                    self.file = AvanteFile(text: "", analysis: [])
                }
            } catch {
                print("Could not read file \(url.lastPathComponent), creating new document. Error: \(error)")
                self.file = AvanteFile(text: "", analysis: [])
            }
        } else {
            print("File does not exist, creating new document: \(url.lastPathComponent)")
            self.file = AvanteFile(text: "", analysis: [])
        }
    }
    
    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            // Truncate all metrics before saving
            var fileToSave = file
            fileToSave.analysis = file.analysis.map { $0.truncated() }
            let data = try encoder.encode(fileToSave)
            
            guard !data.isEmpty, String(data: data, encoding: .utf8) != "null" else {
                print("Warning: Encoded data is empty or null. Aborting save to prevent corruption.")
                return
            }
            
            // Ensure the directory exists
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                print("Created directory: \(directory.path)")
            }
            
            // Write the data atomically
            try data.write(to: url, options: .atomic)
            print("File saved successfully to \(url.lastPathComponent)")
        } catch {
            print("Failed to save file \(url.lastPathComponent). Error: \(error)")
        }
    }
    
    // Method to add analysis metrics and trigger UI updates
    func addAnalysisMetrics(_ newMetrics: [AnalysisMetricsGroup]) {
        file.analysis.append(contentsOf: newMetrics)
        // Trigger UI update by reassigning the file property
        objectWillChange.send()
    }
    
    // Method to update text and trigger UI updates
    func updateText(_ newText: String) {
        file.text = newText
        // Trigger UI update by reassigning the file property
        objectWillChange.send()
    }
    
    func updateURL(to newURL: URL) {
        self.url = newURL
    }
}

// Custom encoder to truncate values to two decimal places
extension AnalysisMetricsGroup {
    func truncated() -> AnalysisMetricsGroup {
        func truncate(_ value: Double) -> Double {
            return Double(Int(value * 100)) / 100.0
        }
        return AnalysisMetricsGroup(
            id: id,
            range: range,
            predictability: truncate(predictability),
            clarity: truncate(clarity),
            flow: truncate(flow)
        )
    }
}
