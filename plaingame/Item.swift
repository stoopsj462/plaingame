//
//  Item.swift
//  plaingame
//
//  Created by jason stoops on 7/28/26.
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
