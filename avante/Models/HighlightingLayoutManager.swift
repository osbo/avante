//
//  HighlightingLayoutManager.swift
//  avante
//
//  Created by Carl Osborne on 6/25/25.
//

import AppKit
import SwiftUI

class HighlightingLayoutManager: NSLayoutManager {
    var analysisData: [Analysis] = []
    var activeHighlight: MetricType? = nil

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        
        guard let activeHighlight = self.activeHighlight, !analysisData.isEmpty else { return }
        
        // --- Pass 1: Draw the solid color backgrounds for all analyzed chunks ---
        for edit in analysisData {
            drawSolidHighlight(for: edit, metric: activeHighlight, at: origin)
        }
        
        // --- Pass 2: Draw the gradient transitions between the chunks ---
        for (index, analysis) in analysisData.enumerated() {
            guard index + 1 < analysisData.count else { continue }
            
            let nextAnalysis = analysisData[index + 1]
            let currentRange = NSRange(location: analysis.range.lowerBound, length: analysis.range.upperBound - analysis.range.lowerBound)
            let nextRange = NSRange(location: nextAnalysis.range.lowerBound, length: nextAnalysis.range.upperBound - nextAnalysis.range.lowerBound)

            // FIX: Check if the end of the current edit and the start of the next edit are on the same line.
            // Get the glyph range for the last character of the current edit.
            let lastCharRange = NSRange(location: NSMaxRange(currentRange) - 1, length: 1)
            let lastGlyphRange = self.glyphRange(forCharacterRange: lastCharRange, actualCharacterRange: nil)
            
            // Get the glyph range for the first character of the next edit.
            let firstCharRange = NSRange(location: nextRange.location, length: 1)
            let firstGlyphRange = self.glyphRange(forCharacterRange: firstCharRange, actualCharacterRange: nil)

            // Ensure the glyph ranges are valid before proceeding.
            guard lastGlyphRange.location != NSNotFound, firstGlyphRange.location != NSNotFound else { continue }

            // Get the line fragment rectangles for each glyph.
            let lastGlyphLineRect = self.lineFragmentRect(forGlyphAt: lastGlyphRange.location, effectiveRange: nil)
            let firstGlyphLineRect = self.lineFragmentRect(forGlyphAt: firstGlyphRange.location, effectiveRange: nil)

            // Only draw the gradient if the two edits are on the same line.
            // We compare the Y-origin of their respective line fragment rectangles.
            if abs(lastGlyphLineRect.origin.y - firstGlyphLineRect.origin.y) < 1.0 {
                
                let startColor = colorFor(value: scoreFor(metric: activeHighlight, in: analysis.metrics))
                let endColor = colorFor(value: scoreFor(metric: activeHighlight, in: nextAnalysis.metrics))
                
                // If chunks are contiguous (no space between them).
                if currentRange.upperBound == nextRange.location {
                    // Draw a small gradient over the first character of the next chunk to blend them.
                    drawGradient(from: startColor, to: endColor, in: firstCharRange, at: origin)
                }
                // If chunks are separated by whitespace.
                else if currentRange.upperBound < nextRange.location {
                    // Draw a gradient over the whitespace between the chunks.
                    let spaceRange = NSRange(location: currentRange.upperBound, length: nextRange.location - currentRange.upperBound)
                    drawGradient(from: startColor, to: endColor, in: spaceRange, at: origin)
                }
            }
        }
    }
    
    // Draws a solid-colored background for a given analysis chunk.
    private func drawSolidHighlight(for analysis: Analysis, metric: MetricType, at origin: CGPoint) {
        let editRange = NSRange(location: analysis.range.lowerBound, length: analysis.range.upperBound - analysis.range.lowerBound)
        let score = scoreFor(metric: metric, in: analysis.metrics)
        let color = colorFor(value: score)
        
        let glyphRangeToDraw = self.glyphRange(forCharacterRange: editRange, actualCharacterRange: nil)
        guard let _ = textContainer(forGlyphAt: glyphRangeToDraw.location, effectiveRange: nil) else { return }

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
        return NSColor(hue: hue, saturation: 0.9, brightness: 0.9, alpha: 0.5)
    }
}
