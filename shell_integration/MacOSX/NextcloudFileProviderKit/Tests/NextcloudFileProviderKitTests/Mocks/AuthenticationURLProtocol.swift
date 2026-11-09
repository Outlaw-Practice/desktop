//  SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Intercepts every request in an authentication test session; no request reaches the network.
final class AuthenticationURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var errors = [String: URLError.Code]()
    nonisolated(unsafe) private static var statusCodes = [String: Int]()
    nonisolated(unsafe) private static var requests = [String: [URLRequest]]()
    nonisolated(unsafe) private static var recoverAfterFirstFailure = Set<String>()
    nonisolated(unsafe) private static var rootETags = [String: String]()
    nonisolated(unsafe) private static var heldHosts = Set<String>()
    nonisolated(unsafe) private static var pending = [String: [AuthenticationURLProtocol]]()

    static func configureStartupRecovery(host: String) {
        configure(host: host, error: .notConnectedToInternet, statusCode: 207)
        lock.withLock { _ = recoverAfterFirstFailure.insert(host) }
    }

    static func configure(host: String, error: URLError.Code?, statusCode: Int = 401, hold: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        errors[host] = error
        statusCodes[host] = statusCode
        requests[host] = []
        rootETags[host] = "root-v1"
        if hold { heldHosts.insert(host) } else { heldHosts.remove(host) }
    }

    static func recordedRequests(host: String) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests[host] ?? []
    }

    static func setRootETag(host: String, etag: String) {
        lock.withLock { rootETags[host] = etag }
    }

    static func release(host: String) {
        let waiting = lock.withLock {
            heldHosts.remove(host)
            return pending.removeValue(forKey: host) ?? []
        }
        waiting.forEach { $0.sendResponse() }
    }

    static func reset(host: String) {
        lock.lock()
        defer { lock.unlock() }
        errors[host] = nil
        statusCodes[host] = nil
        requests[host] = nil
        recoverAfterFirstFailure.remove(host)
        rootETags[host] = nil
        heldHosts.remove(host)
        pending[host] = nil
    }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.lock()
        Self.requests[host, default: []].append(request)
        let hold = Self.heldHosts.contains(host)
        if hold { Self.pending[host, default: []].append(self) }
        Self.lock.unlock()
        if !hold { sendResponse() }
    }

    private func sendResponse() {
        let host = request.url?.host ?? ""
        Self.lock.lock()
        let recovers = Self.recoverAfterFirstFailure.contains(host)
        let error = recovers && (Self.requests[host]?.count ?? 0) > 1 ? nil : Self.errors[host]
        let statusCode = Self.statusCodes[host] ?? 401
        let etag = Self.rootETags[host] ?? "root-v1"
        Self.lock.unlock()
        if let error {
            client?.urlProtocol(self, didFailWithError: URLError(error))
        } else {
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if statusCode == 207 {
                let xml = """
                <?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
                <d:response><d:href>/remote.php/dav/files/test-user/</d:href><d:propstat><d:prop>
                <d:resourcetype><d:collection/></d:resourcetype><d:getetag>\(etag)</d:getetag>
                <oc:fileid>1</oc:fileid><oc:id>00000001mock</oc:id><oc:permissions>RDNVCK</oc:permissions>
                </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>
                """
                client?.urlProtocol(self, didLoad: Data(xml.utf8))
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        Self.lock.withLock {
            Self.pending[request.url?.host ?? ""]?.removeAll { $0 === self }
        }
    }
}
