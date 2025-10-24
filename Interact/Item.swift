//
//  Item.swift
//  Interact
//
//  Created by Ivo Bellin Salarin on 24/10/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
