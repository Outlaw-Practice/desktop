// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: LGPL-3.0-or-later

import Foundation

/// A folder snapshot must be persisted before another read of that folder starts.
/// This prevents a slower, older response from overwriting a newer directory snapshot.
actor RemoteReadCoordinator {
    static let shared = RemoteReadCoordinator()
    private var tails = [String: (id: UUID, task: Task<Void, Never>)]()

    func perform(key: String, operation: @escaping @Sendable () async -> RemoteReadResult) async -> RemoteReadResult {
        let previous = tails[key]?.task
        let id = UUID()
        let result = Task {
            if let previous { await previous.value }
            guard !Task.isCancelled else { return RemoteReadResult(error: .cancelled) }
            return await operation()
        }
        tails[key] = (id, Task { _ = await result.value })
        let value = await withTaskCancellationHandler {
            await result.value
        } onCancel: {
            result.cancel()
        }
        if tails[key]?.id == id { tails[key] = nil }
        return value
    }
}
