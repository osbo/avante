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
        
        // --- Pass 1: Draw the solid color backgrounds for all analyzed chunks ---
        for edit in analysisData {
            drawSolidHighlight(for: edit, metric: activeHighlight, at: origin)
        }
        
        // --- Pass 2: Draw the gradient transitions between the chunks ---
        for (index, edit) in analysisData.enumerated() {
            guard index + 1 < analysisData.count else { continue }
            
            let nextEdit = analysisData[index + 1]
            let currentRange = NSRange(location: edit.range.lowerBound, length: edit.range.upperBound - edit.range.lowerBound)
            let nextRange = NSRange(location: nextEdit.range.lowerBound, length: nextEdit.range.upperBound - nextEdit.range.lowerBound)

            let startColor = colorFor(value: scoreFor(metric: activeHighlight, in: edit.analysisResult))
            let endColor = colorFor(value: scoreFor(metric: activeHighlight, in: nextEdit.analysisResult))
            
            // Case 1: The chunks are separated by a single space.
            if currentRange.upperBound + 1 == nextRange.location {
                let spaceRange = NSRange(location: currentRange.upperBound, length: 1)
                drawGradient(from: startColor, to: endColor, in: spaceRange, at: origin)
            }
            // Case 2: The chunks are immediately adjacent (no space).
            else if currentRange.upperBound == nextRange.location {
                let firstCharRange = NSRange(location: nextRange.location, length: 1)
                drawGradient(from: startColor, to: endColor, in: firstCharRange, at: origin)
            }
        }
    }
    
    // Draws a solid-colored background for a given analysis chunk.
    private func drawSolidHighlight(for edit: AnalyzedEdit, metric: MetricType, at origin: CGPoint) {
        let editRange = NSRange(location: edit.range.lowerBound, length: edit.range.upperBound - edit.range.lowerBound)
        let score = scoreFor(metric: metric, in: edit.analysisResult)
        let color = colorFor(value: score)
        
        let glyphRangeToDraw = self.glyphRange(forCharacterRange: editRange, actualCharacterRange: nil)
        guard let textContainer = textContainer(forGlyphAt: glyphRangeToDraw.location, effectiveRange: nil) else { return }

        // FIX: Use the robust intersection logic to ensure highlights are always tight to the text.
        self.enumerateLineFragments(forGlyphRange: glyphRangeToDraw) { (rect, usedRect, textContainer, lineGlyphRange, stop) in
            
            let lineCharRange = self.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            let lineIntersection = NSIntersectionRange(editRange, lineCharRange)
            
            if lineIntersection.length > 0 {
                let intersectionGlyphRange = self.glyphRange(forCharacterRange: lineIntersection, actualCharacterRange: nil)
                let tightBoundingRect = self.boundingRect(forGlyphRange: intersectionGlyphRange, in: textContainer)
                
                let highlightRect = tightBoundingRect.offsetBy(dx: origin.x, dy: origin.y)
                color.setFill()
                NSBezierPath(rect: highlightRect).fill()
            }
        }
    }
    
    // Draws a horizontal gradient over the rectangle for a specific character range.
    private func drawGradient(from startColor: NSColor, to endColor: NSColor, in range: NSRange, at origin: CGPoint) {
        // Ensure range is valid before proceeding
        guard range.location != NSNotFound, NSMaxRange(range) <= (self.textStorage?.length ?? 0) else { return }
        
        let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard let textContainer = textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil) else { return }
        
        let rect = self.boundingRect(forGlyphRange: glyphRange, in: textContainer).offsetBy(dx: origin.x, dy: origin.y)
        
        // Do not attempt to draw a gradient in an empty rectangle.
        guard rect.width > 0, rect.height > 0 else { return }
        
        let gradient = NSGradient(starting: startColor, ending: endColor)
        gradient?.draw(in: rect, angle: 0)
    }
    
    private func scoreFor(metric: MetricType, in result: AnalysisMetricsGroup) -> Double {
        switch metric {
        case .novelty: return result.novelty
        case .clarity: return result.clarity
        case .flow: return result.flow
        }
    }

    private func colorFor(value: Double) -> NSColor {
        let hue = value * (120.0 / 360.0)
        return NSColor(hue: hue, saturation: 0.9, brightness: 0.9, alpha: 0.65)
    }
}
