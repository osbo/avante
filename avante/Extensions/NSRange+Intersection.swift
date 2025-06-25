//
//  NSRange+Intersection.swift
//  avante
//
//  Created by Carl Osborne on 6/25/25.
//

import Foundation

extension NSRange {
    // Helper property to get the end of a range.
    var upperBound: Int {
        return location + length
    }
    
    // Returns true if this range overlaps with another range at all.
    func intersects(_ other: NSRange) -> Bool {
        // NSIntersectionRange returns a valid range if they overlap,
        // or a range with length 0 if they do not.
        return NSIntersectionRange(self, other).length > 0
    }
}
