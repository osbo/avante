//
//  AvanteDocument.swift
//  avante
//
//  Created by Carl Osborne on 6/20/25.
//

import SwiftUI
import Combine

struct DocumentState: Codable, Equatable {
    var documentId: UUID = UUID()
    var schemaVersion: String = "1.0.0"
    var fullText: String
    var analysisSessions: [AnalysisSession]

    static func == (lhs: DocumentState, rhs: DocumentState) -> Bool {
        lhs.documentId == rhs.documentId
    }
}

struct AnalysisSession: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var startLocation: Int
    var contextSummary: String
    var analyzedEdits: [AnalyzedEdit]

    static func == (lhs: AnalysisSession, rhs: AnalysisSession) -> Bool {
        lhs.id == rhs.id
    }
}

struct AnalyzedEdit: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    // FIX: Add a timestamp to every analysis result.
    var timestamp: Date = Date()
    var range: CodableRange
    var text: String
    var analysisResult: AnalysisMetricsGroup
}

struct CodableRange: Codable, Equatable, Hashable {
    let lowerBound: Int
    let upperBound: Int
}

struct AnalysisMetricsGroup: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    var novelty: Double
    var clarity: Double
    var flow: Double
}

class AvanteDocument: ObservableObject {
    @Published var state: DocumentState
    private(set) var url: URL
    
    init(url: URL) {
        self.url = url
        
        // Use a JSONDecoder that can handle the new timestamp format.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let data = try? Data(contentsOf: url),
           let decodedState = try? decoder.decode(DocumentState.self, from: data) {
            self.state = decodedState
            print("Successfully loaded document state from \(url.lastPathComponent)")
        } else {
            self.state = DocumentState(fullText: "", analysisSessions: [])
            if let initialText = try? String(contentsOf: url, encoding: .utf8) {
                self.state.fullText = initialText
                 print("Loaded document as plain text, creating new analysis state.")
            } else {
                 print("File does not exist or is corrupt, creating new document state: \(url.lastPathComponent)")
            }
        }
    }
    
    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            // Ensure dates are encoded in a standard, readable format.
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            
            try data.write(to: url, options: .atomic)
            print("File saved successfully to \(url.lastPathComponent)")
        } catch {
            print("Failed to save file \(url.lastPathComponent). Error: \(error)")
        }
    }
    
    func updateURL(to newURL: URL) {
        self.url = newURL
    }
}
