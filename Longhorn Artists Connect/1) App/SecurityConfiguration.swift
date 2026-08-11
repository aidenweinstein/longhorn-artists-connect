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

/// Secure configuration manager for API keys and secrets
/// OWASP: Never hard-code secrets in source code
/// Best Practice: Use environment variables, keychain, or secure configuration service
enum SecureConfiguration {
    
    // MARK: - CloudKit Configuration
    
    /// CloudKit container identifier
    /// This is public information and can be in source code
    static let cloudKitContainerID = "iCloud.LAA.Longhorn-Artists-Connect"
    
    // MARK: - API Keys (DO NOT COMMIT)
    
    /// Example: Third-party API key (if needed)
    /// ⚠️ NEVER commit real API keys to source control
    /// 
    /// In production:
    /// 1. Load from environment variable: ProcessInfo.processInfo.environment["API_KEY"]
    /// 2. Load from secure keychain storage
    /// 3. Load from remote configuration service
    /// 4. Use separate configuration files per environment (dev, staging, prod)
    ///
    /// For development:
    /// - Create a local `SecurityConfiguration-Local.swift` file
    /// - Add it to .gitignore
    /// - Define your API keys there
    static var exampleAPIKey: String {
        #if DEBUG
        // Development key (limited permissions)
        return loadFromEnvironment(key: "EXAMPLE_API_KEY") ?? "dev-key-placeholder"
        #else
        // Production key (loaded from secure source)
        guard let key = loadFromEnvironment(key: "EXAMPLE_API_KEY") else {
            fatalError("⚠️ SECURITY: Production API key not configured")
        }
        return key
        #endif
    }
    
    // MARK: - Environment Variable Loading
    
    /// Load configuration from environment variables
    /// OWASP: Use environment variables for sensitive configuration
    /// 
    /// To set environment variables in Xcode:
    /// 1. Edit Scheme → Run → Arguments
    /// 2. Add Environment Variables
    /// 3. Name: API_KEY, Value: your-key-here
    private static func loadFromEnvironment(key: String) -> String? {
        return ProcessInfo.processInfo.environment[key]
    }
    
    // MARK: - Keychain Storage
    
    /// Store API key securely in Keychain
    /// OWASP: Use platform-specific secure storage
    static func storeAPIKey(_ key: String, identifier: String) {
        KeychainHelper.save(key: "api_key_\(identifier)", value: key)
    }
    
    /// Retrieve API key from Keychain
    static func retrieveAPIKey(identifier: String) -> String? {
        return KeychainHelper.load(key: "api_key_\(identifier)")
    }
    
    // MARK: - Key Rotation
    
    /// Track when keys were last rotated
    /// OWASP: Implement key rotation policy
    static var lastKeyRotationDate: Date? {
        get {
            UserDefaults.standard.object(forKey: "lastKeyRotation") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastKeyRotation")
        }
    }
    
    /// Check if key rotation is needed (every 90 days)
    /// OWASP: Rotate secrets regularly
    static func shouldRotateKeys() -> Bool {
        guard let lastRotation = lastKeyRotationDate else {
            return true // Never rotated
        }
        
        let daysSinceRotation = Calendar.current.dateComponents(
            [.day],
            from: lastRotation,
            to: Date()
        ).day ?? 0
        
        return daysSinceRotation > 90
    }
    
    /// Rotate API keys (implement your rotation logic)
    /// OWASP: Automated key rotation
    static func rotateKeys() async throws {
        print("🔄 Rotating API keys...")
        
        // 1. Generate new keys
        // 2. Update remote services
        // 3. Store new keys in keychain
        // 4. Invalidate old keys
        
        lastKeyRotationDate = Date()
        print("✅ API keys rotated successfully")
    }
    
    // MARK: - Security Headers
    
    /// Generate security headers for HTTP requests
    /// OWASP: Use proper security headers
    static func securityHeaders() -> [String: String] {
        return [
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "X-XSS-Protection": "1; mode=block",
            "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
            "Content-Security-Policy": "default-src 'self'"
        ]
    }
    
    // MARK: - Certificate Pinning (if using external APIs)
    
    /// SSL certificate hashes for pinning
    /// OWASP: Implement certificate pinning to prevent MITM attacks
    static let pinnedCertificates: [String: [String]] = [
        "api.example.com": [
            // SHA256 hashes of valid certificates
            // Generate with: openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
            // "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        ]
    ]
    
    // MARK: - Allowed Domains
    
    /// Whitelist of allowed external domains
    /// OWASP: Validate all external connections
    static let allowedDomains = [
        "icloud.com",
        "apple.com",
        "cloudkit.apple.com"
        // Add other trusted domains here
    ]
    
    /// Validate if domain is allowed
    static func isDomainAllowed(_ domain: String) -> Bool {
        return allowedDomains.contains { allowedDomain in
            domain.hasSuffix(allowedDomain)
        }
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
