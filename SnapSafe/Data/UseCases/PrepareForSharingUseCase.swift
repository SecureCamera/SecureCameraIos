//
//  PrepareForSharingUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/9/25.
//

final class PrepareForSharingUseCase {
    // Creates a temporary file for sharing with a UUID filename
    func preparePhotoForSharing(imageData: Data) throws -> URL {
        // Get temporary directory
        let tempDirectory = FileManager.default.temporaryDirectory
        
        // Create UUID filename for sharing
        let uuid = UUID().uuidString
        let tempFileURL = tempDirectory.appendingPathComponent("\(uuid).jpg")
        
        // Write the data to the temporary file
        try imageData.write(to: tempFileURL)
        
        return tempFileURL
    }
}
