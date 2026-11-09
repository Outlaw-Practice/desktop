//  SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: GPL-2.0-or-later

import Alamofire
import AppKit
import FileProvider
import Foundation
import Security
@testable import NextcloudFileProviderKit
@testable import NextcloudKit
import Testing

@Suite(.serialized)
struct AuthenticationFailureTests {
    @Test(arguments: [
        (502, NSFileProviderError.Code.serverUnreachable),
        (504, .serverUnreachable),
        (507, .insufficientQuota),
        (401, .notAuthenticated),
    ])
    func serverErrorsPreserveFileProviderErrorCategories(_ statusCode: Int, _ expected: NSFileProviderError.Code) {
        let error = NKError(errorCode: statusCode, errorDescription: "Mock HTTP failure")
        #expect(error.fileProviderError?.code == expected)
    }

    @MainActor @Test func connectionErrorFitsAuthenticationSheet() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let storyboard = packageRoot.deletingLastPathComponent()
            .appendingPathComponent("NextcloudIntegration/FileProviderUIExt/Authentication/Authentication.storyboard")
        let document = try XMLDocument(contentsOf: storyboard)
        let frame = try #require(document.nodes(forXPath: "//view[@key='view']/rect[@key='frame']").first as? XMLElement)
        let sheetWidth = try #require(Double(frame.attribute(forName: "width")?.stringValue ?? ""))
        let cell = try #require(document.nodes(forXPath: "//textFieldCell[@key='cell']").first as? XMLElement)
        #expect(cell.attribute(forName: "lineBreakMode")?.stringValue == "clipping")

        let label = NSTextField(labelWithString: FileProviderErrorCode.connection.localizedDescription)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        #expect(label.fittingSize.width <= sheetWidth, "The connection error must fit Finder's authentication sheet without clipping.")
    }

    @Test(arguments: [
        (URLError.Code?.some(.notConnectedToInternet), 401, false),
        (.some(.timedOut), 401, false),
        (.some(.cannotConnectToHost), 401, false),
        (nil, 401, false),
        (nil, 500, false),
        (nil, 502, false),
        (nil, 503, false),
        (nil, 504, false),
        (.some(.notConnectedToInternet), 207, true),
    ])
    func setupBoundsStartupRecoveryAndPreservesFailureCategories(_ code: URLError.Code?, _ statusCode: Int, _ recovers: Bool) async throws {
        let identifier = UUID().uuidString.lowercased()
        let host = "\(identifier).invalid"
        let account = Account(user: "test-user", id: "test-user", serverUrl: "https://\(host)", password: "test-password")
        let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(identifier), displayName: "Authentication test")
        let ext = FileProviderExtension(domain: domain)
        let databaseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier)
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        ext.databaseDirectory = databaseDirectory
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticationURLProtocol.self]
        AuthenticationURLProtocol.configure(host: host, error: code, statusCode: statusCode)
        if recovers { AuthenticationURLProtocol.configureStartupRecovery(host: host) }
        let session = NKSession(
            nkCommonInstance: ext.ncKit.nkCommonInstance,
            urlBase: account.serverUrl, user: account.username, userId: account.id,
            password: account.password, account: account.ncKitAccount, userAgent: "AuthenticationTest",
            groupIdentifier: "", httpMaximumConnectionsPerHost: 1,
            httpMaximumConnectionsPerHostInDownload: 1, httpMaximumConnectionsPerHostInUpload: 1,
            sessionDataOverride: Session(configuration: configuration)
        )
        ext.ncKit.nkCommonInstance.nksessions.append(session)
        defer {
            ext.ncKit.nkCommonInstance.nksessions.remove(account: account.ncKitAccount)
            AuthenticationURLProtocol.reset(host: host)
            ext.invalidate()
            ext.dbManager = nil
            try? FileManager.default.removeItem(at: databaseDirectory)
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account.username,
                kSecAttrServer as String: account.serverUrl
            ] as CFDictionary)
        }

        let (completions, continuation) = AsyncStream<NSError?>.makeStream()
        ext.setupDomainAccount(user: account.username, userId: account.id, serverUrl: account.serverUrl, password: account.password) { error in
            continuation.yield(error)
            continuation.finish()
        }
        let (completed, error) = await withTaskGroup(of: (Bool, NSError?).self) { group in
            group.addTask {
                for await error in completions {
                    return (true, error)
                }
                return (false, nil)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return (false, nil)
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }

        #expect(completed, "A failed authentication check must finish promptly, not sleep through minutes of retries.")
        if recovers {
            #expect(error == nil)
            let ready = try await ext.awaitAccount(timeoutNanoseconds: 1)
            #expect(ready.ncKitAccount == account.ncKitAccount)
            #expect(AuthenticationURLProtocol.recordedRequests(host: host).count == 2)
            return
        }
        let failure = try #require(error)
        let expectedCode: FileProviderErrorCode = code != nil || [500, 502, 503, 504].contains(statusCode) ? .connection : .invalidCredentials
        #expect(failure.code == expectedCode.rawValue)
        #expect(failure.localizedDescription == expectedCode.localizedDescription)
        if expectedCode == .connection {
            #expect(failure.localizedDescription.contains("Check your network and try again."))
        }
        if expectedCode == .connection {
            #expect(ext.ncAccount?.ncKitAccount == account.ncKitAccount,
                    "A transport failure must preserve the configured account so normal Finder requests can recover without another app handoff.")
            #expect(ext.dbManager != nil)
            let ready = try await ext.awaitAccount(timeoutNanoseconds: 1)
            #expect(ready.ncKitAccount == account.ncKitAccount)
        } else {
            #expect(ext.ncAccount == nil)
        }
        let requests = AuthenticationURLProtocol.recordedRequests(host: host)
        #expect(requests.count == (code == .notConnectedToInternet ? 2 : 1))
        let request = try #require(requests.first)
        #expect(request.httpMethod == "PROPFIND")
        #expect(request.timeoutInterval == 10)
        #expect(request.value(forHTTPHeaderField: "X-NC-CheckInterceptor") == "false")
        #expect(request.url?.path == "/remote.php/dav/files/test-user")
    }
}
