// SPDX-FileCopyrightText: 2026 Outlaw Practice LLC
// SPDX-License-Identifier: LGPL-3.0-or-later

import Foundation

/// Domain-owned remote scan state. Enumerators may finish and be invalidated between reads.
public final class WorkingSetRefreshState: @unchecked Sendable {
    struct Snapshot: Sendable {
        var updated: [SendableItemMetadata] = []
        var deleted: [SendableItemMetadata] = []
        var completedAt: Date?
        var hadFailure = false
    }

    private let lock = NSLock()
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var retiringTask: Task<Void, Never>?
    private var snapshot = Snapshot()
    private var startedAt: Date?
    private var retryAttempted = false

    public init() {}

    /// A new server notification supersedes a scan that may already have read the changed folder.
    func requestRefresh() {
        lock.withLock {
            generation = UUID()
            task?.cancel()
            if let task { retiringTask = task }
            task = nil
            snapshot = Snapshot()
            startedAt = nil
            retryAttempted = false
        }
    }

    func waitForCurrentScan() async {
        let current = lock.withLock { task ?? retiringTask }
        await current?.value
    }

    func changes(
        since date: Date,
        scan: @escaping @Sendable (@escaping @Sendable ([SendableItemMetadata]) -> Void) async -> Snapshot,
        signal: @escaping @Sendable () -> Void
    ) -> Snapshot {
        lock.withLock {
            if task == nil, startedAt == nil || snapshot.completedAt.map({ date >= $0 }) == true {
                let identifier = UUID()
                generation = identifier
                let start = Date()
                startedAt = start
                snapshot = Snapshot()
                let previous = retiringTask
                retiringTask = nil
                task = Task {
                    await previous?.value
                    guard !Task.isCancelled else { return }
                    let result = await scan { updates in
                        let shouldSignal = self.lock.withLock {
                            guard self.generation == identifier else { return false }
                            self.snapshot.updated = updates
                            // Every changed batch must wake the framework. Dropping a burst's
                            // last notification delays those changes until the whole scan ends.
                            return !updates.isEmpty
                        }
                        if shouldSignal { signal() }
                    }
                    let shouldSignal = self.lock.withLock {
                        guard self.generation == identifier else { return false }
                        self.snapshot = result
                        self.snapshot.completedAt = start
                        if !result.hadFailure { self.task = nil }
                        return true
                    }
                    if shouldSignal { signal() }
                    if result.hadFailure {
                        let mayRetry = self.lock.withLock {
                            guard self.generation == identifier else { return false }
                            guard !self.retryAttempted else {
                                self.task = nil
                                return false
                            }
                            self.retryAttempted = true
                            return true
                        }
                        guard mayRetry else { return }
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        let retry = self.lock.withLock {
                            guard self.generation == identifier else { return false }
                            self.startedAt = nil
                            self.task = nil
                            return true
                        }
                        if retry { signal() }
                    }
                }
            }
            return snapshot
        }
    }
}
