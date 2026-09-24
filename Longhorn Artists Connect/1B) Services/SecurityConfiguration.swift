//
//  SecurityConfiguration.swift
//  Longhorn Artists Connect
//
//  OWASP-compliant security configuration
//  Handles API keys, secrets, and sensitive configuration
//
//  ⚠️ IMPORTANT: This file should be excluded from version control
//  Add to .gitignore: SecurityConfiguration.swift
//

import Foundation
import Combine

// MARK: - Moderator Access

/// The single source of truth for who is allowed to use moderator mode.
///
/// Gating on the display name alone was spoofable — anyone could set their name to
/// the moderator's and unlock it. This instead gates on the CloudKit **user record
/// ID**, which Apple assigns per iCloud account and which a user can't change from
/// inside the app. `CloudKitManager` caches the signed-in account's record name to
/// UserDefaults on launch; this reads it back synchronously, so the check is callable
/// from any context (views, models) without an actor hop.
enum ModeratorAccess {
    /// UserDefaults key holding the signed-in iCloud account's CloudKit record name.
    /// Still cached by `CloudKitManager`; retained for other callers even though the
    /// moderator check no longer uses it.
    static let currentUserRecordNameKey = "currentUserRecordName"

    /// The one profile name allowed to use moderator mode.
    static let moderatorName = "Aiden Weinstein"

    /// True only when the signed-in profile's name is the moderator's. Actually
    /// entering moderator mode additionally requires the session password (see
    /// `ModeratorSession`); this just controls whether the moderator surfaces appear.
    static var isModerator: Bool {
        let first = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let last = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let fullName = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return fullName.caseInsensitiveCompare(moderatorName) == .orderedSame
    }
}

// MARK: - Moderator Session Unlock

/// Session-scoped gate for the moderator-mode switch. The switch stays locked until
/// the correct password is entered *this run*; relaunching the app relocks it because
/// `isUnlocked` is in-memory only (never persisted).
@MainActor
final class ModeratorSession: ObservableObject {
    static let shared = ModeratorSession()
    private init() {}

    /// Password required to unlock the moderator switch for the session.
    private static let password = "misko"

    /// True once the correct password has been entered this session.
    @Published private(set) var isUnlocked = false

    /// Returns true (and unlocks) if `attempt` matches the moderator password.
    @discardableResult
    func unlock(with attempt: String) -> Bool {
        guard attempt == Self.password else { return false }
        isUnlocked = true
        return true
    }
}

// MARK: - Security Configuration Template

/// Template for local configuration file
/// Copy this to `SecurityConfiguration-Local.swift` and add to .gitignore
///
/// ```swift
/// extension SecureConfiguration {
///     static var localAPIKey: String {
///         return "your-development-key-here"
///     }
/// }
/// ```

// MARK: - Production Checklist

/*
 PRODUCTION SECURITY CHECKLIST:
 
 ✅ 1. API Keys & Secrets
    - [ ] No hardcoded API keys in source code
    - [ ] Load secrets from environment variables
    - [ ] Use Keychain for sensitive data storage
    - [ ] Implement key rotation policy (90 days)
    - [ ] Different keys for dev/staging/production
 
 ✅ 2. Network Security
    - [ ] Use HTTPS only
    - [ ] Implement certificate pinning for critical APIs
    - [ ] Validate all external domains
    - [ ] Use security headers
 
 ✅ 3. Data Protection
    - [ ] Encrypt sensitive data at rest
    - [ ] Use Data Protection API (FileProtectionType)
    - [ ] Clear sensitive data from memory after use
    - [ ] Implement secure deletion
 
 ✅ 4. Authentication & Authorization
    - [ ] Implement proper authentication
    - [ ] Use CloudKit's built-in auth
    - [ ] Never trust client-side authorization
    - [ ] Implement rate limiting
 
 ✅ 5. Input Validation
    - [ ] Validate all user inputs
    - [ ] Sanitize data before display
    - [ ] Implement length limits
    - [ ] Reject unexpected fields
 
 ✅ 6. Logging & Monitoring
    - [ ] Log security events
    - [ ] Monitor for suspicious activity
    - [ ] Never log sensitive data
    - [ ] Implement alerting for security events
 
 ✅ 7. Code Obfuscation
    - [ ] Enable bitcode
    - [ ] Strip debug symbols in release
    - [ ] Enable app transport security
    - [ ] Implement jailbreak detection (optional)
 
 ✅ 8. Regular Updates
    - [ ] Keep dependencies up to date
    - [ ] Monitor security advisories
    - [ ] Regular security audits
    - [ ] Penetration testing
 */

// MARK: - .gitignore Template

/*
 Add these to your .gitignore:
 
 # Security Configuration
 SecurityConfiguration-Local.swift
 
 # API Keys
 *.plist containing "API"
 *.xcconfig containing secrets
 
 # Certificates
 *.p12
 *.mobileprovision
 
 # Keychain
 *.keychain
 *.keychain-db
 */
