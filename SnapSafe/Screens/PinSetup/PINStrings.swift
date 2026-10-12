//
//  PINStrings.swift
//  SnapSafe
//

import Foundation

enum PINStrings {
    static let shortPinWarning = "Short PINs are less secure. Consider using 6+ characters."

    /// Mirrors Android's `pin_alphanumeric_help_message`. 62^4 = 14,776,336.
    static let alphanumericHelpMessage: LocalizedStringResource = """
        Alphanumeric PINs allow letters (a-z, A-Z) in addition to digits (0-9).

        This dramatically increases security:

        • A 4-digit numeric PIN has 10,000 possible combinations
        • A 4-character alphanumeric PIN has over 14 million combinations

        Using letters and numbers together makes your PIN much harder to guess or brute-force.
        """
}
