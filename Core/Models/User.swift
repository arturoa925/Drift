//
//  User.swift
//  Dritft
//
//  Created by Arturo Ayala on 5/28/26.
//

import Foundation

/// The local device user. Drift has no accounts — this just identifies
/// one installation so preferences and history can be scoped to it.
struct User: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date

    init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }
}
