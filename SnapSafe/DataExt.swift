//
//  DataExt.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation

extension Data {
    /// URL-safe base64
    func base64URLEncodedString() -> String {
        let b64 = self.base64EncodedString()
        return b64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Initialize from URL-safe base64 (padding optional).
    init?(base64URLString s: String) {
        var str = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Re-add padding if missing
        let pad = (4 - (str.count % 4)) % 4
        if pad > 0 { str.append(String(repeating: "=", count: pad)) }
        guard let data = Data(base64Encoded: str) else { return nil }
        self = data
    }
}
