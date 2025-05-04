//
//  FileManager.swift
//  Snap Safe
//
//  Created by Bill Booth on 5/3/25.
//

import Foundation

//class SecureFileManager {
//    private let fileManager = FileManager.default
//    
//    // Get a secure directory that's not backed up to iCloud
//    private func getSecureDirectory() throws -> URL {
//        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
//            throw NSError(domain: "com.securecamera", code: -1, userInfo: nil)
//        }
//        
//        let secureDirectory = documentsDirectory.appendingPathComponent("SecurePhotos", isDirectory: true)
//        
//        if !fileManager.fileExists(atPath: secureDirectory.path) {
//            try fileManager.createDirectory(at: secureDirectory, withIntermediateDirectories: true, attributes: nil)
//            
//            // Set the "do not backup" attribute
//            var resourceValues = URLResourceValues()
//            resourceValues.isExcludedFromBackup = true
//            var secureDirectoryWithAttributes = secureDirectory
//            try secureDirectoryWithAttributes.setResourceValues(resourceValues)
//        }
//        
//        return secureDirectory
//    }
//    
//    func saveEncryptedPhoto(_ encryptedData: Data, withMetadata metadata: [String: Any]) throws {
//        let secureDirectory = try getSecureDirectory()
//        let filename = UUID().uuidString
//        let fileURL = secureDirectory.appendingPathComponent("\(filename).secphoto")
//        
//        // Save encrypted photo with file protection
//        try encryptedData.write(to: fileURL, options: .completeFileProtection)
//        
//        // Save metadata separately
//        let metadataURL = secureDirectory.appendingPathComponent("\(filename).metadata")
//        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [])
//        try metadataData.write(to: metadataURL, options: .completeFileProtection)
//    }
//    
//    func loadEncryptedPhoto(filename: String) throws -> (encryptedData: Data, metadata: [String: Any]) {
//        let secureDirectory = try getSecureDirectory()
//        let fileURL = secureDirectory.appendingPathComponent("\(filename).secphoto")
//        let metadataURL = secureDirectory.appendingPathComponent("\(filename).metadata")
//        
//        // Load encrypted photo
//        let encryptedData = try Data(contentsOf: fileURL)
//        
//        // Load metadata
//        let metadataData = try Data(contentsOf: metadataURL)
//        guard let metadata = try JSONSerialization.jsonObject(with: metadataData, options: []) as? [String: Any] else {
//            throw NSError(domain: "com.securecamera", code: -2, userInfo: nil)
//        }
//        
//        return (encryptedData, metadata)
//    }
//    
//    func deleteAllPhotos() throws {
//        let secureDirectory = try getSecureDirectory()
//        let contents = try fileManager.contentsOfDirectory(at: secureDirectory, includingPropertiesForKeys: nil)
//        
//        for fileURL in contents {
//            try fileManager.removeItem(at: fileURL)
//        }
//    }
//}
