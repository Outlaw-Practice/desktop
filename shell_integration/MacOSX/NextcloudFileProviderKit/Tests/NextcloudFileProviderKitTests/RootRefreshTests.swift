// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import Alamofire
import FileProvider
import Foundation
@testable import NextcloudFileProviderKit
import NextcloudFileProviderKitMocks
@testable import NextcloudKit
import XCTest

final class RootRefreshTests: XCTestCase {
    private var previousBlockSync: Any?

    override func setUp() {
        super.setUp()
        previousBlockSync = UserDefaults.standard.object(forKey: "blockSync")
        UserDefaults.standard.removeObject(forKey: "blockSync")
    }

    override func tearDown() {
        if let previousBlockSync {
            UserDefaults.standard.set(previousBlockSync, forKey: "blockSync")
        } else {
            UserDefaults.standard.removeObject(forKey: "blockSync")
        }
        super.tearDown()
    }

    private func makeExtension(hold: Bool = false) -> (FileProviderExtension, String) {
        let identifier = UUID().uuidString.lowercased()
        let host = "\(identifier).invalid"
        let account = Account(user: "test-user", id: "test-user", serverUrl: "https://\(host)", password: "test-password")
        let domain = NSFileProviderDomain(identifier: .init(identifier), displayName: "Root poll fixture")
        let ext = FileProviderExtension(domain: domain)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticationURLProtocol.self]
        AuthenticationURLProtocol.configure(host: host, error: nil, statusCode: 207, hold: hold)
        ext.ncKit.nkCommonInstance.nksessions.append(NKSession(
            nkCommonInstance: ext.ncKit.nkCommonInstance,
            urlBase: account.serverUrl, user: account.username, userId: account.id,
            password: account.password, account: account.ncKitAccount, userAgent: "RootRefreshTest",
            groupIdentifier: "", httpMaximumConnectionsPerHost: 1,
            httpMaximumConnectionsPerHostInDownload: 1, httpMaximumConnectionsPerHostInUpload: 1,
            sessionDataOverride: Session(configuration: configuration)
        ))
        ext.ncAccount = account
        ext.ignoredFiles = IgnoredFilesMatcher(ignoreList: [], log: FileProviderLogMock())
        return (ext, host)
    }

    private func cleanup(_ ext: FileProviderExtension, host: String) {
        ext.invalidate()
        if let account = ext.ncAccount {
            ext.ncKit.nkCommonInstance.nksessions.remove(account: account.ncKitAccount)
        }
        AuthenticationURLProtocol.release(host: host)
        AuthenticationURLProtocol.reset(host: host)
    }

    @MainActor private func snapshot(_ ext: FileProviderExtension) -> WorkingSetRefreshState.Snapshot {
        ext.workingSetRefresh.changes(since: .distantPast, scan: { _ in .init() }, signal: {})
    }

    @MainActor private func completeSnapshot(_ ext: FileProviderExtension) async -> Date? {
        _ = snapshot(ext)
        await ext.workingSetRefresh.waitForCurrentScan()
        return snapshot(ext).completedAt
    }

    @MainActor func testRootETagChangesInvalidateTheScanButUnchangedETagsDoNot() async {
        let (ext, host) = makeExtension()
        defer { cleanup(ext, host: host) }
        let initial = await completeSnapshot(ext)
        XCTAssertNotNil(initial)
        await ext.refreshRoot()
        XCTAssertNil(snapshot(ext).completedAt)
        let completed = await completeSnapshot(ext)
        XCTAssertNotNil(completed)
        await ext.refreshRoot()
        XCTAssertEqual(snapshot(ext).completedAt, completed)
        AuthenticationURLProtocol.setRootETag(host: host, etag: "root-v2")
        await ext.refreshRoot()
        XCTAssertNil(snapshot(ext).completedAt)
        let requests = AuthenticationURLProtocol.recordedRequests(host: host)
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.first?.httpMethod, "PROPFIND")
        XCTAssertEqual(requests.first?.timeoutInterval, 10)
    }

    @MainActor func testBlockedOrInvalidatedExtensionDoesNotPoll() async {
        let (ext, host) = makeExtension()
        defer { cleanup(ext, host: host) }
        UserDefaults.standard.set(true, forKey: "blockSync")
        await ext.refreshRoot()
        XCTAssertTrue(AuthenticationURLProtocol.recordedRequests(host: host).isEmpty)
        UserDefaults.standard.removeObject(forKey: "blockSync")
        ext.invalidate()
        await ext.refreshRoot()
        XCTAssertTrue(AuthenticationURLProtocol.recordedRequests(host: host).isEmpty)
    }

    @MainActor func testInFlightPollIsSingleAndCannotPublishAfterInvalidation() async {
        let (ext, host) = makeExtension(hold: true)
        defer { cleanup(ext, host: host) }
        let first = Task { await ext.refreshRoot() }
        let deadline = ContinuousClock().now + .seconds(2)
        while AuthenticationURLProtocol.recordedRequests(host: host).isEmpty, ContinuousClock().now < deadline {
            await Task.yield()
        }
        XCTAssertEqual(AuthenticationURLProtocol.recordedRequests(host: host).count, 1)
        await ext.refreshRoot()
        XCTAssertEqual(AuthenticationURLProtocol.recordedRequests(host: host).count, 1)
        ext.invalidate()
        let completed = await completeSnapshot(ext)
        XCTAssertNotNil(completed)
        AuthenticationURLProtocol.release(host: host)
        await first.value
        XCTAssertEqual(snapshot(ext).completedAt, completed)
    }
}
