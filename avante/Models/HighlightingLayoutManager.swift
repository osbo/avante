//
//  HighlightingLayoutManager.swift
//  avante
//
//  Created by Carl Osborne on 6/25/25.
//

import AppKit
import SwiftUI

class HighlightingLayoutManager: NSLayoutManager {
    var analysisData: [AnalyzedEdit] = []
    var activeHighlight: MetricType? = nil

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        
        guard let activeHighlight = self.activeHighlight, !analysisData.isEmpty else { return }
        
        let charRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        for edit in analysisData {
            let editRange = NSRange(location: edit.range.lowerBound, length: edit.range.upperBound - edit.range.lowerBound)
            let intersection = NSIntersectionRange(charRange, editRange)

            if intersection.length > 0 {
                let score = scoreFor(metric: activeHighlight, in: edit.analysisResult)
                let color = colorFor(value: score)
                
                let glyphRangeToDraw = self.glyphRange(forCharacterRange: editRange, actualCharacterRange: nil)
                
                guard let textContainer = self.textContainer(forGlyphAt: glyphRangeToDraw.location, effectiveRange: nil) else { continue }
                
                // This method correctly handles ranges that wrap across multiple lines.
                self.enumerateLineFragments(forGlyphRange: glyphRangeToDraw) { (rect, usedRect, textContainer, lineGlyphRange, stop) in
                    
                    // Calculate the intersection of the edit range with this line fragment
                    let lineCharRange = self.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
                    let lineIntersection = NSIntersectionRange(editRange, lineCharRange)
                    
                    if lineIntersection.length > 0 {
                        // Convert the intersection back to glyph range for this line
                        let intersectionGlyphRange = self.glyphRange(forCharacterRange: lineIntersection, actualCharacterRange: nil)
                        
                        // Calculate the precise bounding box for just the intersecting glyphs
                        let tightBoundingRect = self.boundingRect(forGlyphRange: intersectionGlyphRange, in: textContainer)
                        
                        let highlightRect = tightBoundingRect.offsetBy(dx: origin.x, dy: origin.y)
                        color.setFill()
                        NSBezierPath(rect: highlightRect).fill()
                    }
                }
            }
        }
    }
    
    private func scoreFor(metric: MetricType, in result: AnalysisMetricsGroup) -> Double {
        switch metric {
        case .novelty:
            return result.novelty
        case .clarity:
            return result.clarity
        case .flow:
            return result.flow
        }
    }

    private func colorFor(value: Double) -> NSColor {
        // Hue range: Green (~120 degrees) to Red (0 degrees).
        let hue = value * (120.0 / 360.0)
        
        return NSColor(
            hue: hue,
            saturation: 0.9,
            brightness: 0.9,
            alpha: 0.6
        )
    }
}
