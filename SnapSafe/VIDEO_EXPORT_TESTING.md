# Video Export Testing on iOS Simulator

This guide explains how to test video export functionality in SnapSafe on the iOS Simulator, even without camera hardware.

## Quick Answer: Yes, you can test video export on simulator! 📱

While simulators don't have physical cameras, you can test all video export functionality using the tools provided in this project.

## Testing Methods

### 1. Interactive Testing (Recommended)

**Access the Video Export Test View:**
1. Open SnapSafe in the simulator
2. Navigate to the camera view
3. Long-press the settings gear icon (⚙️) for 2 seconds
4. This opens the Video Export Test interface

**What you can test:**
- Video creation with programmatically generated content
- Video export to Photos Library
- Encrypted video creation and playback
- Memory usage during video processing
- File format validation

### 2. Automated Testing with Swift Testing

Run the test suite to verify video export functionality:

```swift
// In Xcode, run the VideoExportTests test suite
// Tests include:
// - testVideoCreation()
// - testVideoExport()
// - testEncryptedVideoCreation()
// - testVideoPlayerWithEncryptedContent()
```

### 3. Console Testing

From Xcode's debug console, run:

```swift
// Paste this in the Xcode console while app is running:
if #available(iOS 18.0, *) {
    Task { await runVideoExportTests() }
}
```

## What Gets Tested

### ✅ Video Creation
- Generates a 3-second test video with animated rainbow gradient
- 1080x1920 resolution (portrait)
- H.264 encoding
- 30fps framerate

### ✅ Video Export
- Tests `PHPhotoLibrary` integration
- Handles permission requests
- Validates file format compatibility
- Tests sharing workflow

### ✅ Encrypted Video Support
- Creates encrypted `.secv` files
- Tests `EncryptedVideoDataSource` functionality
- Validates AES-GCM encryption
- Tests `AVPlayer` integration with custom resource loader

### ✅ Memory Management
- Monitors memory usage during video processing
- Tests for memory leaks
- Validates efficient chunk-based decryption

## Expected Results on Simulator

### Photos Library Access
- **First run**: May prompt for Photos permission
- **Simulator**: Permission dialog might not appear (expected)
- **Result**: Tests handle this gracefully and continue

### Performance
- **Simulator**: May be faster/slower than real devices
- **Memory**: Different usage patterns than hardware
- **Result**: All functionality works, performance metrics may differ

### Video Playback
- **Encrypted videos**: Full support via custom `EncryptedVideoDataSource`
- **Standard videos**: Native `AVPlayer` support
- **Result**: Both work perfectly on simulator

## Troubleshooting

### "Photos access not authorized" 
This is expected on simulator. The test will mark this as a conditional pass.

### Video creation fails
Check available disk space in simulator. Video files need temporary storage.

### Long press doesn't work
Make sure you're in DEBUG mode and using iOS 18.0+ simulator.

## Production Considerations

### Remove Debug Code
Before release, ensure debug gestures and test views are properly gated:

```swift
#if DEBUG
// Test code only in debug builds
#endif
```

### Real Device Testing
While simulator testing covers most functionality, always test on real devices for:
- Actual camera integration
- Performance characteristics
- Battery impact
- Hardware-specific behaviors

## File Structure

```
VideoExportTestHelper.swift     // Core testing utilities
VideoExportTests.swift          // Swift Testing test suite
VideoExportTestView.swift       // Interactive test interface
RunVideoExportTests.swift       // Console test runner
```

## Summary

**Yes, you can comprehensively test video export on simulator!** The provided tools test:

- ✅ Video creation and encoding
- ✅ Export to Photos Library
- ✅ Encrypted video workflows  
- ✅ Memory management
- ✅ File format validation
- ✅ Sharing functionality

The only limitation is the lack of actual camera hardware, but all video processing, encryption, export, and playback functionality can be thoroughly tested.

**Quick Start**: Long-press the ⚙️ settings icon in camera view → Video Export Test