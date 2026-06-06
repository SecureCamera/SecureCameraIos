//
//  AuthorizePinUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/4/25.
//


public final class AuthorizePinUseCase: @unchecked Sendable {
	private let authRepository: AuthorizationRepository
	private let pinRepository: PinRepository

	public init(
        authRepository: AuthorizationRepository,
		pinRepository: PinRepository,
	) {
		self.authRepository = authRepository
		self.pinRepository = pinRepository
	}

	/// Authorizes user by verifying the PIN and updates the authorization state if successful.
	/// - Parameter pin: The PIN entered by the user
	/// - Returns: The stored `HashedPin` if the PIN is correct; otherwise `nil`.
	public func authorizePin(_ pin: String) async -> HashedPin? {
		let hashedPin = await pinRepository.getHashedPin()
		let isValid = await pinRepository.verifySecurityPin(pin)

		guard isValid, let hashedPin else {
			return nil
		}
        
        await self.authRepository.authorizeSession()
		await authRepository.resetFailedAttempts()
		return hashedPin
	}
}
