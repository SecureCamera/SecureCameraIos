//
//  SecurityOverlayViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/8/25.
//

import Combine
import FactoryKit
import SwiftUI
import Logging

// MARK: - Security Overlay State

public enum SecurityOverlayState {
    case normal
    case screenRecording
    case requiresAuthentication
    case privacyShield

    var priority: Int {
        switch self {
        case .screenRecording: 3
        case .requiresAuthentication: 2
        case .privacyShield: 1
        case .normal: 0
        }
    }
}

// MARK: - Security Overlay View Model

@MainActor
final class SecurityOverlayViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published public var currentOverlayState: SecurityOverlayState = .normal
    @Published public var dismissAllSheets: Bool = false
    @Published public var dismissAllAlerts: Bool = false

    // MARK: - Private Properties

    private var wasInBackground: Bool = false
    private var isInactive: Bool = false
    private var needsAuthenticationAfterBackground: Bool = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Dependencies

    @Injected(\.authorizationRepository)
    private var authorizationRepository: AuthorizationRepository

    @Injected(\.settingsDataSource)
    private var settings: SettingsDataSource
    
    @Injected(\.invalidateSessionUseCase)
    private var invalidateSessionUseCase: InvalidateSessionUseCase

    private let screenCaptureManager = ScreenCaptureManager.shared

    // MARK: - Initialization

    init() {
        setupObservers()
        setupNotificationObservers()
    }

    // MARK: - Public Methods

    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        Logger.security.debug("SecurityOverlay scene phase changed", metadata: [
            "newPhase": .string(String(describing: newPhase))
        ])

        Task {
            switch newPhase {
            case .active:
                isInactive = false
                await handleWillEnterForeground()
            case .background:
                isInactive = false
                await handleDidEnterBackground()
            case .inactive:
                isInactive = true
                // Dismiss any active alerts before showing privacy shield
                dismissAllAlerts = true
                await updateOverlayState() // Show privacy shield for task switcher
                
                // Reset dismiss flag after a brief delay
                Task {
                    try await Task.sleep(for: .milliseconds(100))
                    await MainActor.run {
                        self.dismissAllAlerts = false
                    }
                }
            @unknown default:
                break
            }
        }
    }

    func authenticationComplete() async {
        wasInBackground = false
        needsAuthenticationAfterBackground = false
        await updateOverlayState()
    }

    func resetState() async {
        dismissAllSheets = false
        dismissAllAlerts = false
        wasInBackground = false
        needsAuthenticationAfterBackground = false
        isInactive = false
        await updateOverlayState()
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Monitor authorization state changes
        authorizationRepository.isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nowAuthorized in
                Task { @MainActor in
                    if(nowAuthorized) {
                        await self?.authenticationComplete()
                    } else {
                        await self?.updateOverlayState()
                    }
                }
            }
            .store(in: &cancellables)

        // Monitor intro completion state
        settings.hasCompletedIntro
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.updateOverlayState()
                }
            }
            .store(in: &cancellables)

        // Monitor screen recording state
        screenCaptureManager.$isScreenBeingRecorded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.updateOverlayState()
                }
            }
            .store(in: &cancellables)
    }

    private func setupNotificationObservers() {
        // Listen for app lifecycle notifications
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleDidEnterBackground()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleWillEnterForeground()
                }
            }
            .store(in: &cancellables)
    }

    private func handleDidEnterBackground() async {
        Logger.security.debug("SecurityOverlay: App entered background")
        wasInBackground = true
        await updateOverlayState()
    }

    private func handleWillEnterForeground() async {
        Logger.security.debug("SecurityOverlay: App will enter foreground", metadata: [
            "wasInBackground": .stringConvertible(wasInBackground)
        ])

        // Get current values from repositories
        let hasCompletedIntro = getCurrentValue(from: settings.hasCompletedIntro)
        let hasValidSession = await authorizationRepository.checkSessionValidity()
        
        if !hasValidSession, wasInBackground, hasCompletedIntro {
            Logger.security.info("SecurityOverlay: Requiring authentication after background")
            
            invalidateSessionUseCase.invalidateSession()
            
            // Set authentication required flag
            needsAuthenticationAfterBackground = true

            // Dismiss sheets first
            dismissAllSheets = true

            // Reset dismiss flag after a short delay
            Task {
                try await Task.sleep(for: .milliseconds(100))
                await MainActor.run {
                    self.dismissAllSheets = false
                }
            }
        } else {
            // Clear the background flag if not requiring authentication
            wasInBackground = false
        }

        // Update last active time regardless
        authorizationRepository.keepAliveSession()
        await updateOverlayState()
    }

    private func updateOverlayState() async {
        let states = await determineActiveStates()
        let highestPriorityState = states.max(by: { $0.priority < $1.priority }) ?? .normal

        if currentOverlayState != highestPriorityState {
            Logger.security.info("SecurityOverlay state changing", metadata: [
                "from": .string(String(describing: currentOverlayState)),
                "to": .string(String(describing: highestPriorityState))
            ])
            currentOverlayState = highestPriorityState
        }
    }

    private func determineActiveStates() async -> [SecurityOverlayState] {
        var states: [SecurityOverlayState] = [.normal]

        // Screen recording takes highest priority
        if screenCaptureManager.isScreenBeingRecorded {
            states.append(.screenRecording)
        }

        // Authentication required after background (highest priority after screen recording)
        if needsAuthenticationAfterBackground {
            states.append(.requiresAuthentication)
            return states // Don't show other overlays when authentication is required
        }

        // Get current values from repositories
        let hasCompletedIntro = getCurrentValue(from: settings.hasCompletedIntro)
        let isAuthorized = await authorizationRepository.checkSessionValidity()

        // General authentication required (for normal PIN verification flow)
        if hasCompletedIntro && !isAuthorized {
            states.append(.requiresAuthentication)
            return states // Don't show other overlays when authentication is required
        }

        // Privacy shield when in task switcher (inactive) or backgrounded
        if isInactive || wasInBackground {
            states.append(.privacyShield)
        }

        return states
    }

    // MARK: - Helper Methods

    private func getCurrentValue<T>(from publisher: AnyPublisher<T, Never>) -> T {
        var currentValue: T!
        let cancellable = publisher.sink { value in
            currentValue = value
        }
        cancellable.cancel()
        return currentValue
    }
}
