//  SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

///
/// Error codes originating from the file provider extension module.
///
enum FileProviderErrorCode: Int {
    case connection
    case invalidCredentials
    case missingAccountInformation

    var localizedDescription: String {
        switch self {
            case .connection:
                String(localized: "Could not connect to Nextcloud. Check your network and try again.")
            case .invalidCredentials:
                String(localized: "Authentication failed due to invalid credentials.")
            case .missingAccountInformation:
                String(localized: "The account information is not available.")
        }
    }
}

extension NSError {
    ///
    /// Convenience initializer for custom error objects to pass over XPC.
    ///
    convenience init(_ code: FileProviderErrorCode) {
        self.init(domain: Bundle.main.bundleIdentifier ?? "com.nextcloud.desktopclient.FileProviderExt", code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: code.localizedDescription])
    }
}
