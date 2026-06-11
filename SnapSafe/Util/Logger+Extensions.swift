//
//  Logger+Extensions.swift
//  SnapSafe
//
//  Created by Claude on 9/10/25.
//

import Logging

extension Logger {
    /// Logger for encryption and cryptographic operations
    static let encryption = Logger(label: "com.snapsafe.encryption")
    
    /// Logger for security operations (PIN, auth, access control)
    static let security = Logger(label: "com.snapsafe.security")
    
    /// Logger for camera operations and photo capture
    static let camera = Logger(label: "com.snapsafe.camera")
    
    /// Logger for storage and file operations
    static let storage = Logger(label: "com.snapsafe.storage")
    
    /// Logger for user interface events and navigation
    static let ui = Logger(label: "com.snapsafe.ui")
    
    /// Logger for general application events
    static let app = Logger(label: "com.snapsafe.app")

    /// Logger for video operations (encryption, decryption, playback)
    static let video = Logger(label: "com.snapsafe.video")

    /// Logger for media gallery operations
    static let media = Logger(label: "com.snapsafe.media")
    
}

// MARK: - Convenience Methods for Common Patterns
extension Logger {
    /// Log an operation with timing information
    func logOperation<T>(_ operation: String, level: Logger.Level = .info, execute: () throws -> T) rethrows -> T {
        let startTime = DispatchTime.now()
        
        self.log(level: level, "Starting operation", metadata: [
            "operation": .string(operation)
        ])
        
        do {
            let result = try execute()
            let endTime = DispatchTime.now()
            let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000 // Convert to milliseconds
            
            self.log(level: level, "Operation completed successfully", metadata: [
                "operation": .string(operation),
                "duration_ms": .stringConvertible(String(format: "%.2f", duration))
            ])
            
            return result
        } catch {
            let endTime = DispatchTime.now()
            let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            
            self.error("Operation failed", metadata: [
                "operation": .string(operation),
                "duration_ms": .stringConvertible(String(format: "%.2f", duration)),
                "error": .string(String(describing: error))
            ])
            
            throw error
        }
    }
    
    /// Log an async operation with timing information
    func logAsyncOperation<T>(_ operation: String, level: Logger.Level = .info, execute: () async throws -> T) async rethrows -> T {
        let startTime = DispatchTime.now()
        
        self.log(level: level, "Starting async operation", metadata: [
            "operation": .string(operation)
        ])
        
        do {
            let result = try await execute()
            let endTime = DispatchTime.now()
            let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            
            self.log(level: level, "Async operation completed successfully", metadata: [
                "operation": .string(operation),
                "duration_ms": .stringConvertible(String(format: "%.2f", duration))
            ])
            
            return result
        } catch {
            let endTime = DispatchTime.now()
            let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            
            self.error("Async operation failed", metadata: [
                "operation": .string(operation),
                "duration_ms": .stringConvertible(String(format: "%.2f", duration)),
                "error": .string(String(describing: error))
            ])
            
            throw error
        }
    }
    
    /// Log data size information
    func logDataOperation(_ operation: String, dataSize: Int, level: Logger.Level = .debug) {
        self.log(level: level, "Data operation", metadata: [
            "operation": .string(operation),
            "size_bytes": .stringConvertible(dataSize),
            "size_kb": .stringConvertible(String(format: "%.2f", Double(dataSize) / 1024.0))
        ])
    }
    
}