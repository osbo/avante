//
//  AppDelegate.swift
//  avante
//
//  Created by Carl Osborne on 6/28/25.
//

import AppKit
import SwiftUI
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        
        // Ensure the main window is brought to the front before loading content.
        // This is important if the app is already running but the window is in the background.
        if let window = sender.windows.first {
             window.makeKeyAndOrderFront(nil)
        }

        // Post the notification for the view model to handle the file opening.
        NotificationCenter.default.post(name: .openFileFromFinder, object: url)
        
        // Return true to confirm we've handled the event.
        return true
    }

    // This delegate method handles re-opening the main window after it has been closed,
    // for example, by clicking on the app's dock icon when no windows are visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Since we now use a single `Window` scene, `sender.windows.first`
            // will safely refer to our main application window.
            if let window = sender.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
