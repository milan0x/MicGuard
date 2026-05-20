//
//  MGLog.swift
//  MicGuard
//
//  Compile-out-in-release logging wrapper. Use MGLog.debug instead of NSLog
//  for diagnostics — Release builds drop the calls entirely so user-facing
//  Console.app stays clean.
//

import Foundation

enum MGLog {
    /// Debug-only log. Compiled out in Release builds.
    /// Use `@autoclosure` so callers can pass string interpolation without paying
    /// the cost of building the message when DEBUG is off.
    @inlinable
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("%@", message())
        #endif
    }
}
