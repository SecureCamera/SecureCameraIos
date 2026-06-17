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
    
}