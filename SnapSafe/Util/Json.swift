//
//  Json.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/4/25.
//

func jsonEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}


