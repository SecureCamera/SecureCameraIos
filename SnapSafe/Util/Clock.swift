//
//  Clock.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/4/25.
//


public protocol Clock: Sendable {
	var now: Date { get }
}

final class SystemClock: Clock {
    var now: Date {
        return Date()
    }
}
