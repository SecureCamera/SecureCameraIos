//
//  CombineExt.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/6/25.
//

import Combine


extension Publisher {
    /// Awaits the first value this publisher emits.
    func firstValue() async -> Output? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                var cancellable: AnyCancellable?
                cancellable = self.first().sink(
                    receiveCompletion: { _ in
                        continuation.resume(returning: nil)
                        cancellable?.cancel()
                    },
                    receiveValue: { value in
                        continuation.resume(returning: value)
                        cancellable?.cancel()
                    }
                )
            }
        } onCancel: {
            // Handle task cancellation by cancelling the subscription
        }
    }
    
    /// Awaits the first value this publisher emits, or returns `defaultValue` if none are emitted.
    func firstValue(or defaultValue: Output) async -> Output {
        // Use AsyncSequence bridge
        if let value = try? await self.values.first(where: { _ in true }) {
            return value
        } else {
            return defaultValue
        }
    }
}
