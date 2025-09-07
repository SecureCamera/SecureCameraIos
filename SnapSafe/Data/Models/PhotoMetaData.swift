//
//  PhotoMetaData.swift
//  SnapSafe
//
//  Created by Claude on 9/7/25.
//

import Foundation
import CoreLocation
import UIKit

public struct PhotoMetaData {
    public let name: String
    public let resolution: CGSize
    public let dateTaken: Date?
    public let location: CLLocationCoordinate2D?
    public let orientation: CGImagePropertyOrientation?
}

public struct CapturedImage {
    public let sensorBitmap: UIImage
    public let timestamp: Date
    public let rotationDegrees: Int
}
