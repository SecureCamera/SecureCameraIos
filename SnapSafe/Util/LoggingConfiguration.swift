//
//  LoggingConfiguration.swift
//  SnapSafe
//
//  Created by Claude on 9/10/25.
//

import Foundation
import Logging

/// Centralized logging configuration for SnapSafe
struct LoggingConfiguration {
    
    /// Configure logging for the entire application
    static func configure() {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            
            // Set log level based on build configuration
            #if DEBUG
            handler.logLevel = .debug
            #else
            handler.logLevel = .info
            #endif
            
            return handler
        }
        
        // Log configuration startup
        Logger.app.info("Logging system configured", metadata: [
            "build_config": .string(buildConfiguration),
            "log_level": .string(String(describing: currentLogLevel))
        ])
    }
    
    /// Get the current build configuration
    private static var buildConfiguration: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
    
    /// Get the current log level
    private static var currentLogLevel: Logger.Level {
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }
    
    /// Update log level dynamically (useful for settings)
    static func setLogLevel(_ level: Logger.Level) {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = level
            return handler
        }
        
        Logger.app.info("Log level updated", metadata: [
            "new_level": .string(String(describing: level))
        ])
    }
}

// MARK: - Log Level Utilities
extension Logger.Level {
    /// Human-readable description for settings UI
    var displayName: String {
        switch self {
        case .trace:
            return "Trace"
        case .debug:
            return "Debug"
        case .info:
            return "Info"
        case .notice:
            return "Notice"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        case .critical:
            return "Critical"
        }
    }
    
    /// All available log levels for settings picker
    static var allCases: [Logger.Level] {
        return [.trace, .debug, .info, .notice, .warning, .error, .critical]
    }
}