//
//  HashedPin.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation

public struct HashedPin: Equatable, Sendable, Codable {
    public let salt: Data
    public let hash: Data
    public init(salt: Data, hash: Data) {
        self.salt = salt
        self.hash = hash
    }
}
