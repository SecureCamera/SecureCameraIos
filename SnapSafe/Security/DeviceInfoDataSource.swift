//
//  DeviceInfoDataSource.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import UIKit
import CryptoKit

final class DeviceInfoDataSource {
    
    func getDeviceIdentifier() async -> Data {
        let vendorId = await UIDevice.current.identifierForVendor?.uuidString ?? ""
        let manufacturer = "Apple"
        let model = DeviceInfoDataSource.machineIdentifier()
        
        let id = vendorId + manufacturer + model
        let digest = SHA512.hash(data: Data(id.utf8))
        return Data(digest)
    }
    
    /// Returns a stable hardware identifier string (e.g., "iPhone16,2")
    private static func machineIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
