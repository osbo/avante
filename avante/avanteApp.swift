//
//  avanteApp.swift
//  avante
//
//  Created by Carl Osborne on 6/19/25.
//

import SwiftUI

@main
struct avanteApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: AvanteDocument()) { file in
            EditView(document: file.$document)
        }
    }
}
