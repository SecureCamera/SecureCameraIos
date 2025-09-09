//
//  PinStrengthCheckUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/8/25.
//

import Foundation

final class PinStrengthCheckUseCase {
    func isPinStrongEnough(_ pin: String) -> Bool {
        // Check if PIN is at least 4 digits long and contains only digits
        guard pin.count >= 4, pin.allSatisfy({ $0.isNumber }) else {
            return false
        }
        
        // Check if all digits are the same (e.g., "1111")
        if let firstChar = pin.first, pin.allSatisfy({ $0 == firstChar }) {
            return false
        }
        
        // Check if PIN is a sequence (ascending or descending)
        let digits = pin.compactMap { $0.wholeNumberValue }
        let isAscendingSequence = zip(digits, digits.dropFirst()).allSatisfy { $1 - $0 == 1 }
        let isDescendingSequence = zip(digits, digits.dropFirst()).allSatisfy { $1 - $0 == -1 }
        
        if isAscendingSequence || isDescendingSequence {
            return false
        }
        
        // Check against blacklist
        if Self.blackList.contains(pin) {
            return false
        }
        
        return true
    }
    
    private static let blackList: [String] = [
        "1212",
        "6969",
    ]
}
