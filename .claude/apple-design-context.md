# Apple Design Context

## Product
- **Name**: SnapSafe
- **Description**: Privacy-focused camera app that encrypts photos and videos locally using AES-256-GCM; no cloud, no leaks
- **Category**: Photography (public.app-category.photography)
- **Stage**: Active development (v1.3.0, shipping)

## Platforms
| Platform | Supported | Min OS | Notes |
|----------|-----------|--------|-------|
| iOS      | Yes       | 18.5   | Portrait-only (locked) |
| iPadOS   | Yes       | 18.5   | All orientations; just added in v1.3.x |
| macOS    | No        | —      | Catalyst disabled |
| tvOS     | No        | —      | |
| watchOS  | No        | —      | |
| visionOS | No        | —      | |

## Technology
- **UI Framework**: SwiftUI (primary) + UIKit (UIViewRepresentable for AVFoundation camera preview)
- **Architecture**: Single-window, custom programmatic NavigationStack (AppNavigationState)
- **Apple Technologies**: AVFoundation, AVKit, CryptoKit, Security (Secure Enclave), CoreLocation, Vision (face detection), AppIntents (Action Button), Photos/PhotosUI

## Design System
- **Base**: Custom; no design system library
- **Accent Color**: #3DDC84 (brand green) — no dark mode variant defined in asset catalog
- **Typography**: Mix of `.font(.system(size: X))` hardcoded sizes (60+ instances) and semantic styles (`.body`, `.caption`, etc., 74 instances) — inconsistent
- **Dark Mode**: User-selectable (system/light/dark) via Settings; `preferredColorScheme` applied at root
- **Dynamic Type**: Not supported — hardcoded font sizes do not scale

## Accessibility
- **Target Level**: Baseline (aspirational)
- **Current State**: **None** — zero `.accessibilityLabel`, `.accessibilityHint`, or `.accessibilityValue` modifiers found in the entire app
- **Key Considerations**: VoiceOver unusable; camera controls, gallery cells, and PIN entry all unlabeled
- **Regulatory**: No known regulatory requirements stated

## Users
- **Primary Persona**: Privacy-conscious individuals who want to capture sensitive photos/videos without risk of cloud upload, screenshot capture, or unauthorized access
- **Key Use Cases**: Capture photo/video → stored encrypted locally → view in secure gallery → optionally share (decrypted) → security features (PIN, poison pill, privacy shield)
- **Known Challenges**: High security requirements create UX tension; PIN entry must be custom (no system keyboard for screenshots); camera access is the primary surface and must feel fast and trustworthy
