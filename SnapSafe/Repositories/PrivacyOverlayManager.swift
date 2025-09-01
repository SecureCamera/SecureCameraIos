//
//  PrivacyOverlayManager.swift
//  SnapSafe
//
//  Created by Claude Code on 6/25/25.
//

import Combine
import SwiftUI
import UIKit

/// Manager for privacy overlay window that prevents app content from appearing in task switcher
final class PrivacyOverlayManager: ObservableObject {
    static let shared = PrivacyOverlayManager()

    private var overlayWindow: UIWindow?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        // Use the earliest possible notification to show privacy shield
        // This fires BEFORE iOS takes the snapshot for task switcher
        NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)
            .sink { [weak self] _ in
                print("PrivacyOverlayManager: protectedDataWillBecomeUnavailable - showing overlay")
                self?.showPrivacyOverlay()
            }
            .store(in: &cancellables)

        // Backup trigger in case protectedDataWillBecomeUnavailable doesn't fire
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                print("PrivacyOverlayManager: willResignActive - showing overlay (backup)")
                self?.showPrivacyOverlay()
            }
            .store(in: &cancellables)

        // Hide overlay when app becomes active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                print("PrivacyOverlayManager: didBecomeActive - hiding overlay")
                self?.hidePrivacyOverlay()
            }
            .store(in: &cancellables)

        // Also hide on protectedDataDidBecomeAvailable
        NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
            .sink { [weak self] _ in
                print("PrivacyOverlayManager: protectedDataDidBecomeAvailable - hiding overlay")
                self?.hidePrivacyOverlay()
            }
            .store(in: &cancellables)
    }

    private func showPrivacyOverlay() {
        DispatchQueue.main.async { [weak self] in
            self?.createAndShowOverlayWindow()
        }
    }

    private func hidePrivacyOverlay() {
        DispatchQueue.main.async { [weak self] in
            self?.destroyOverlayWindow()
        }
    }

    private func createAndShowOverlayWindow() {
        guard overlayWindow == nil else {
            print("PrivacyOverlayManager: Overlay already showing")
            return
        }

        print("PrivacyOverlayManager: Creating privacy overlay window")

        // Create window that covers entire screen and stays on top
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            overlayWindow = UIWindow(windowScene: windowScene)
            overlayWindow?.windowLevel = UIWindow.Level.alert + 1000 // Ensure it's above everything
            overlayWindow?.isHidden = false
            overlayWindow?.backgroundColor = .black

            // Create the privacy shield view controller
            let privacyVC = PrivacyShieldViewController()
            overlayWindow?.rootViewController = privacyVC

            print("PrivacyOverlayManager: Privacy overlay window created and shown")
        } else {
            print("PrivacyOverlayManager: ERROR - Could not find window scene")
        }
    }

    private func destroyOverlayWindow() {
        guard overlayWindow != nil else {
            print("PrivacyOverlayManager: No overlay to hide")
            return
        }

        print("PrivacyOverlayManager: Destroying privacy overlay window")
        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
        overlayWindow = nil
    }
}

/// UIViewController that displays the privacy shield
private class PrivacyShieldViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupPrivacyShieldView()
    }

    private func setupPrivacyShieldView() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.98)

        // Create the privacy shield content
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // App icon
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: "lock.shield.fill")
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconImageView)

        // App name
        let appNameLabel = UILabel()
        appNameLabel.text = "SnapSafe"
        appNameLabel.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        appNameLabel.textColor = .white
        appNameLabel.textAlignment = .center
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(appNameLabel)

        // Privacy message
        let messageLabel = UILabel()
        messageLabel.text = "The camera app that minds its own business."
        messageLabel.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        messageLabel.textColor = .gray
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(messageLabel)

        // Setup constraints
        NSLayoutConstraint.activate([
            // Container centered
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            containerView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),

            // Icon
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 100),
            iconImageView.heightAnchor.constraint(equalToConstant: 100),

            // App name
            appNameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 30),
            appNameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            appNameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            // Message
            messageLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 20),
            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            messageLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
    }
}
