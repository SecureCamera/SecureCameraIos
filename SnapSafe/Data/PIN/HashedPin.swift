//
//  HashedPin.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

public struct HashedPin: Codable, Equatable, Sendable {
    let hash: String
    let salt: String
}
