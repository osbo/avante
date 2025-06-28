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

// Defines custom Notification names for various actions
extension Notification.Name {
    static let saveAction = Notification.Name("com.carlosborne.avante.saveAction")
    static let renameAction = Notification.Name("com.carlosborne.avante.renameAction")
    static let toggleHighlight = Notification.Name("com.carlosborne.avante.toggleHighlight")
    static let clearHighlights = Notification.Name("com.carlosborne.avante.clearHighlights")
    static let triggerRename = Notification.Name("com.carlosborne.avante.triggerRename")
    static let reanalyzeAction = Notification.Name("com.carlosborne.avante.reanalyzeAction")
    static let undoAction = Notification.Name("com.carlosborne.avante.undoAction")
    static let redoAction = Notification.Name("com.carlosborne.avante.redoAction")
    static let openFileFromFinder = Notification.Name("com.carlosborne.avante.openFileFromFinder")
}
