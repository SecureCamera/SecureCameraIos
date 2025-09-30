//
//  PhotoMetaData.swift
//  SnapSafe
//
//  Created by Claude on 9/7/25.
//

import Foundation
import CoreLocation
import UIKit


struct CapturedImage {
    let sensorBitmap: UIImage
    let timestamp: Date
    let rotationDegrees: Int
}
