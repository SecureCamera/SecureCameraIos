//
//  Clock.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/4/25.
//


import Foundation

public protocol Clock: Sendable {
    /// Wall-clock time. Suitable for display and persistence, but NOT for
    /// security-sensitive elapsed-time decisions because the user (or an attacker
    /// with device access) can change it.
    var now: Date { get }

    /// Monotonic time in seconds since an arbitrary fixed point. Always advances,
    /// is unaffected by wall-clock changes, and continues across device sleep.
    /// Use this for any elapsed-time check that gates security behavior such as
    /// session timeout or PIN backoff.
    var monotonicNow: TimeInterval { get }
}

final class SystemClock: Clock {
    var now: Date {
        return Date()
    }

    var monotonicNow: TimeInterval {
        var ts = timespec()
        // CLOCK_UPTIME_RAW is monotonic and continues counting while the
        // device is asleep, which is what we want for security timers.
        clock_gettime(CLOCK_UPTIME_RAW, &ts)
        return TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1_000_000_000
    }
}
