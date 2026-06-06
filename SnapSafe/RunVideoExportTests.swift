// Development/testing tool — compiled in Debug builds only, never ships.
#if DEBUG
//
//  RunVideoExportTests.swift
//  SnapSafe
//
//  Created by Assistant on 5/25/26.
//

import Foundation

/// Simple script to run video export tests from Xcode console
/// Run this in Xcode console: po runVideoExportTests()
@available(iOS 18.0, *)
func runVideoExportTests() async {
    print("🎬 Starting Video Export Tests for Simulator...")
    print("=====================================")
    
    #if DEBUG
    let results = await VideoExportValidator.runAllTests()
    
    print("🎯 All tests completed!")
    print("=====================================")
    
    for result in results {
        let status = result.success ? "PASS" : "FAIL"
        let emoji = result.success ? "✅" : "❌"
        print("\(emoji) \(result.testName): \(status)")
        if !result.success {
            print("   Error: \(result.message)")
        }
    }
    
    let passCount = results.filter { $0.success }.count
    let totalCount = results.count
    
    print("\n📊 Test Summary: \(passCount)/\(totalCount) tests passed")
    print("\n💡 To access interactive tests, long-press the settings gear icon (⚙️) in the camera view")
    #else
    print("❌ Tests are only available in DEBUG builds")
    #endif
}

/// Quick access function that can be called from anywhere in debug builds
#if DEBUG
@available(iOS 18.0, *)
func quickVideoTest() async {
    await runVideoExportTests()
}
#endif
#endif
