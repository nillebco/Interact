//
//  Item.swift
//  Interact
//
//  Created by Ivo Bellin Salarin on 24/10/2025.
//

import Foundation

final class Item: Identifiable {
    let id: UUID
    var timestamp: Date

    init(id: UUID = UUID(), timestamp: Date) {
        self.id = id
        self.timestamp = timestamp
    }
}
