// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import FileProvider
import Foundation
@testable import NextcloudFileProviderKit
import XCTest

final class XPCConnectionLifecycleTests: XCTestCase {
    func testOverlappingInterruptionAndInvalidationCallbacksAreSafe() {
        let domain = NSFileProviderDomain(identifier: .init(UUID().uuidString), displayName: "XPC lifecycle test")
        let ext = FileProviderExtension(domain: domain)
        // A suspended anonymous listener keeps all traffic local and avoids real services.
        let peer = NSXPCListener.anonymous()
        let connections = (0..<128).map { _ in NSXPCConnection(listenerEndpoint: peer.endpoint) }
        defer {
            for connection in connections {
                connection.interruptionHandler = nil
                connection.invalidationHandler = nil
                connection.exportedObject = nil
                connection.invalidate()
            }
            peer.invalidate()
            ext.app = nil
            ext.invalidate()
        }
        for connection in connections {
            XCTAssertTrue(ext.listener(ext.listener, shouldAcceptNewConnection: connection))
        }
        DispatchQueue.concurrentPerform(iterations: connections.count * 2) { index in
            let connection = connections[index / 2]
            if index.isMultiple(of: 2) {
                connection.interruptionHandler?()
            } else {
                connection.invalidationHandler?()
            }
        }
        XCTAssertTrue(ext.connections.isEmpty)
    }
}
