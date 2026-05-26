# SECV Video Implementation Plan for SnapSafe iOS

This document outlines the implementation plan for adding video capture, encryption, and playback functionality to SnapSafe iOS, based on the Android reference implementation.

## Current Status

The iOS app already has the following video-related functionality:
- ✅ Basic video capture functionality (`VideoCaptureService`)
- ✅ Video mode switching in camera UI
- ✅ `VideoDef` model structure
- ✅ Movie output setup in `CameraDeviceService`
- ✅ Audio input handling for video recording

## Implementation Phases

### Phase 1: SECV File Format Implementation ✅
**Goal**: Implement the SECV (Secure Encrypted Camera Video) file format for iOS

**Files to create/modify:**
1. `SnapSafe/Data/Models/SECVFileFormat.swift` - SECV constants and utilities
2. `SnapSafe/Data/Models/VideoDef.swift` - Enhance with encryption support
3. `SnapSafe/Data/Encryption/VideoEncryptionService.swift` - Chunked encryption service

**Implementation details:**
- Create SECV trailer structure with magic, version, chunk size, etc.
- Implement chunk index table for seeking
- Add encryption/decryption helpers for 1MB chunks
- Use AES-GCM with per-chunk IVs and authentication tags

### Phase 2: Video Encryption Service
**Goal**: Implement post-recording chunked encryption

**Files to create:**
1. `SnapSafe/Data/Encryption/VideoEncryptionService.swift` - Main encryption service
2. `SnapSafe/Data/Encryption/StreamingVideoEncryptor.swift` - Chunked encryption
3. `SnapSafe/Data/Encryption/StreamingVideoDecryptor.swift` - Chunked decryption for playback

**Implementation approach:**
- Use `DispatchIO` for efficient file streaming
- Process videos in 1MB chunks to avoid memory issues
- Store temporary unencrypted files in app-private storage
- Delete temp files after successful encryption
- Handle crashes and partial encryption states

### Phase 3: Video Playback
**Goal**: Add encrypted video playback using AVPlayer with custom data source

**Files to create:**
1. `SnapSafe/Util/EncryptedVideoDataSource.swift` - Custom AVAssetResourceLoaderDelegate
2. `SnapSafe/Screens/PhotoDetail/VideoPlayerView.swift` - Video playback UI
3. `SnapSafe/Screens/PhotoDetail/EnhancedPhotoDetailViewModel.swift` - Add video support

**Implementation approach:**
- Create custom `AVAssetResourceLoaderDelegate` for decryption
- Implement chunk caching for smooth playback
- Add playback controls (play/pause, seek, volume)
- Handle encrypted vs unencrypted video files

### Phase 4: Gallery Integration
**Goal**: Integrate videos into the existing gallery view

**Files to modify:**
1. `SnapSafe/Screens/Gallery/SecureGalleryViewModel.swift` - Add videos array
2. `SnapSafe/Screens/Gallery/SecureGalleryView.swift` - Mixed photo/video grid
3. `SnapSafe/Screens/Gallery/PhotoCell.swift` - Add video thumbnail support

**Implementation approach:**
- Create unified media model that handles both photos and videos
- Add video thumbnail generation
- Implement video duration overlay
- Add video playback indicator

### Phase 5: Video Sharing
**Goal**: Add secure video sharing functionality

**Files to create:**
1. `SnapSafe/Util/VideoSharingHelper.swift` - Video sharing utilities
2. `SnapSafe/Screens/PhotoDetail/VideoShareView.swift` - Sharing UI

**Implementation approach:**
- Create temporary decrypted copies for sharing
- Clean up temp files after sharing
- Add sharing progress indicators
- Handle large video files appropriately

### Phase 6: Error Handling & Cleanup
**Goal**: Add robust error handling and cleanup

**Files to modify:**
1. `SnapSafe/Data/Encryption/VideoEncryptionService.swift` - Add error recovery
2. `SnapSafe/Screens/Camera/VideoCaptureService.swift` - Handle encryption failures
3. `SnapSafe/Util/FileCleanupService.swift` - Cleanup orphaned files

**Implementation approach:**
- Detect and handle partial encryption states
- Clean up temp files on app launch
- Add error recovery for interrupted encryption
- Implement background cleanup service

## Technical Approach

### Encryption Strategy
- **Post-recording encryption**: Record to temp `.mov` file, then encrypt to `.secv`
- **Chunked processing**: 1MB chunks with AES-256-GCM
- **Trailer format**: Metadata at end to avoid file rewriting
- **Per-chunk authentication**: Detect tampering at chunk level

### Playback Strategy
- **Custom AVAssetResourceLoaderDelegate**: Decrypt chunks on-demand
- **Chunk caching**: Cache recently decrypted chunks for smooth playback
- **Seeking support**: Use chunk index table for O(1) seeking

### Security Considerations
- Temp files only exist briefly in app-private storage
- Use same key derivation as photo encryption (PBKDF2 from PIN)
- Memory-safe implementation with no large allocations
- Proper cleanup of sensitive data

## Testing Strategy

1. **Unit tests**: SECV format parsing, encryption/decryption
2. **Integration tests**: Video capture → encryption → playback workflow
3. **Performance tests**: Large video handling (1GB+ files)
4. **Crash recovery tests**: Handle interrupted encryption
5. **UI tests**: Video playback controls and gallery integration

## Android Reference Implementation

The Android implementation uses:
- **CameraX** for video recording
- **ExoPlayer** with custom `DataSource` for playback
- **Chunked streaming encryption** with 1MB chunks
- **Trailer format** for efficient metadata storage
- **Foreground service** for encryption to handle large files

Key files to reference:
- `SecureCameraAndroid/app/src/main/kotlin/com/darkrockstudios/app/securecamera/security/streaming/SecvFileFormat.kt`
- `SecureCameraAndroid/app/src/main/kotlin/com/darkrockstudios/app/securecamera/security/streaming/ChunkedStreamingEncryptor.kt`
- `SecureCameraAndroid/app/src/main/kotlin/com/darkrockstudios/app/securecamera/playback/EncryptedVideoDataSource.kt`
- `SecureCameraAndroid/docs/Video Encryption.md`

## Implementation Notes

The iOS implementation will follow the same architectural patterns as Android but use iOS-specific APIs:
- **AVFoundation** instead of CameraX
- **AVPlayer** instead of ExoPlayer
- **DispatchIO** instead of Java NIO
- **CryptoKit** instead of Java Crypto APIs

The SECV file format remains identical between platforms for cross-platform compatibility.