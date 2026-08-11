//
//  SecurityManager.swift
//  Longhorn Artists Connect
//
//  OWASP-compliant security manager for input validation, rate limiting, and sensitive data handling
//  Follows iOS security best practices and CloudKit security model
//

import Foundation
import CloudKit
import CryptoKit

/// Centralized security manager following OWASP best practices
/// Handles: Input validation, rate limiting, sensitive data protection, and audit logging
@MainActor
class SecurityManager {
    static let shared = SecurityManager()
    
    // MARK: - Rate Limiting
    
    /// Rate limiter to prevent abuse and DoS attacks
    /// OWASP: Implement rate limiting to prevent brute force and abuse
    private class RateLimiter {
        private var requestTimestamps: [String: [Date]] = [:]
        private let lock = NSLock()
        
        /// Check if action is rate-limited
        /// - Parameters:
        ///   - identifier: Unique identifier (user ID, device ID, or action type)
        ///   - maxRequests: Maximum number of requests allowed
        ///   - timeWindow: Time window in seconds
        /// - Returns: True if allowed, false if rate limited
        func checkRateLimit(for identifier: String, maxRequests: Int, timeWindow: TimeInterval) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            
            let now = Date()
            let windowStart = now.addingTimeInterval(-timeWindow)
            
            // Get or create timestamp array for this identifier
            var timestamps = requestTimestamps[identifier] ?? []
            
            // Remove timestamps outside the window
            timestamps.removeAll { $0 < windowStart }
            
            // Check if limit exceeded
            guard timestamps.count < maxRequests else {
                print("⚠️ RATE LIMIT: \(identifier) exceeded \(maxRequests) requests in \(timeWindow)s")
                return false
            }
            
            // Add current timestamp
            timestamps.append(now)
            requestTimestamps[identifier] = timestamps
            
            return true
        }
        
        /// Reset rate limit for identifier (useful after successful authentication)
        func resetRateLimit(for identifier: String) {
            lock.lock()
            defer { lock.unlock() }
            requestTimestamps.removeValue(forKey: identifier)
        }
        
        /// Clean up old timestamps periodically
        func cleanup() {
            lock.lock()
            defer { lock.unlock() }
            
            let cutoff = Date().addingTimeInterval(-3600) // 1 hour ago
            for (key, timestamps) in requestTimestamps {
                let filtered = timestamps.filter { $0 > cutoff }
                if filtered.isEmpty {
                    requestTimestamps.removeValue(forKey: key)
                } else {
                    requestTimestamps[key] = filtered
                }
            }
        }
    }
    
    private let rateLimiter = RateLimiter()
    
    // MARK: - Rate Limit Configurations (OWASP Recommended)
    
    /// Rate limit for CloudKit writes (posts, updates)
    /// OWASP: Stricter limits for write operations
    private let writeRateLimit = (maxRequests: 10, timeWindow: 60.0) // 10 writes per minute
    
    /// Rate limit for CloudKit reads (fetches, queries)
    /// OWASP: More lenient for reads but still protected
    private let readRateLimit = (maxRequests: 100, timeWindow: 60.0) // 100 reads per minute
    
    /// Rate limit for authentication attempts
    /// OWASP: Very strict to prevent brute force
    private let authRateLimit = (maxRequests: 5, timeWindow: 300.0) // 5 attempts per 5 minutes
    
    /// Rate limit for message sending
    /// OWASP: Prevent spam and abuse
    private let messageRateLimit = (maxRequests: 20, timeWindow: 60.0) // 20 messages per minute
    
    // MARK: - Device Identifier
    
    /// Get a consistent device identifier for rate limiting
    /// OWASP: Use device-specific identifier, not easily spoofable
    private var deviceIdentifier: String {
        // Use keychain for persistent device ID
        if let storedID = KeychainHelper.load(key: "deviceID") {
            return storedID
        }
        
        // Generate new device ID
        let newID = UUID().uuidString
        KeychainHelper.save(key: "deviceID", value: newID)
        return newID
    }
    
    // MARK: - Rate Limiting Public API
    
    /// Check rate limit for CloudKit write operation
    func checkWriteRateLimit(userID: String? = nil) -> Bool {
        let identifier = userID ?? deviceIdentifier
        return rateLimiter.checkRateLimit(
            for: "write_\(identifier)",
            maxRequests: writeRateLimit.maxRequests,
            timeWindow: writeRateLimit.timeWindow
        )
    }
    
    /// Check rate limit for CloudKit read operation
    func checkReadRateLimit(userID: String? = nil) -> Bool {
        let identifier = userID ?? deviceIdentifier
        return rateLimiter.checkRateLimit(
            for: "read_\(identifier)",
            maxRequests: readRateLimit.maxRequests,
            timeWindow: readRateLimit.timeWindow
        )
    }
    
    /// Check rate limit for message sending
    func checkMessageRateLimit(userID: String) -> Bool {
        return rateLimiter.checkRateLimit(
            for: "message_\(userID)",
            maxRequests: messageRateLimit.maxRequests,
            timeWindow: messageRateLimit.timeWindow
        )
    }
    
    /// Check rate limit for authentication attempts
    func checkAuthRateLimit(identifier: String) -> Bool {
        return rateLimiter.checkRateLimit(
            for: "auth_\(identifier)",
            maxRequests: authRateLimit.maxRequests,
            timeWindow: authRateLimit.timeWindow
        )
    }
    
    // MARK: - Input Validation (OWASP)
    
    /// Validate and sanitize text input
    /// OWASP: Always validate and sanitize user input
    /// - Parameters:
    ///   - input: Raw user input
    ///   - maxLength: Maximum allowed length
    ///   - allowedCharacters: Regex pattern for allowed characters
    ///   - fieldName: Name of field for error reporting
    /// - Returns: Sanitized input or nil if invalid
    func validateAndSanitizeText(
        _ input: String,
        maxLength: Int,
        allowedCharacters: String = ".*", // Allow all by default
        fieldName: String
    ) -> String? {
        // Trim whitespace
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check length
        guard trimmed.count <= maxLength else {
            print("⚠️ VALIDATION: \(fieldName) exceeds max length \(maxLength)")
            return nil
        }
        
        // Check minimum length (non-empty for required fields)
        guard !trimmed.isEmpty else {
            print("⚠️ VALIDATION: \(fieldName) is empty")
            return nil
        }
        
        // Check allowed characters
        if let regex = try? NSRegularExpression(pattern: "^\(allowedCharacters)$") {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if regex.firstMatch(in: trimmed, options: [], range: range) == nil {
                print("⚠️ VALIDATION: \(fieldName) contains invalid characters")
                return nil
            }
        }
        
        // Remove potentially dangerous characters (XSS prevention)
        // OWASP: Encode output and remove script tags
        var sanitized = trimmed
        sanitized = sanitized.replacingOccurrences(of: "<script>", with: "", options: .caseInsensitive)
        sanitized = sanitized.replacingOccurrences(of: "</script>", with: "", options: .caseInsensitive)
        sanitized = sanitized.replacingOccurrences(of: "javascript:", with: "", options: .caseInsensitive)
        
        return sanitized
    }
    
    /// Validate email format
    /// OWASP: Use proper email validation
    func validateEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    /// Validate URL format
    /// OWASP: Validate URLs to prevent injection attacks
    func validateURL(_ urlString: String, allowedSchemes: [String] = ["http", "https"]) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        
        return allowedSchemes.contains(scheme)
    }
    
    /// Validate UUID format
    func validateUUID(_ uuidString: String) -> Bool {
        return UUID(uuidString: uuidString) != nil
    }
    
    /// Validate date is within reasonable range
    func validateDate(_ date: Date, minYearOffset: Int = -5, maxYearOffset: Int = 10) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        guard let minDate = calendar.date(byAdding: .year, value: minYearOffset, to: now),
              let maxDate = calendar.date(byAdding: .year, value: maxYearOffset, to: now) else {
            return false
        }
        
        return date >= minDate && date <= maxDate
    }
    
    // MARK: - Submission Validation
    
    /// Validate submission data before saving
    /// OWASP: Comprehensive input validation
    struct SubmissionValidationResult {
        let isValid: Bool
        let errors: [String]
    }
    
    func validateSubmission(
        title: String,
        details: String,
        type: MediaType,
        additionalFields: [String: Any] = [:]
    ) -> SubmissionValidationResult {
        var errors: [String] = []
        
        // Validate title (OWASP: Length and content validation)
        if validateAndSanitizeText(
            title,
            maxLength: 200,
            allowedCharacters: "[\\w\\s\\-.,!?'\"()&]+",
            fieldName: "title"
        ) == nil {
            errors.append("Title is invalid or too long (max 200 characters)")
        }
        
        // Validate details ONLY when provided. `details` is optional in this app —
        // submissions store their real content in the title + type-specific fields
        // and pass an empty details string. `validateAndSanitizeText` rejects empty
        // input, so validating it unconditionally would silently fail every post.
        if !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if validateAndSanitizeText(
                details,
                maxLength: 5000,
                fieldName: "details"
            ) == nil {
                errors.append("Details are invalid or too long (max 5000 characters)")
            }
        }
        
        // Type-specific validation
        switch type {
        case .film:
            // Validate film-specific fields
            if let ageRating = additionalFields["ageRating"] as? String {
                let validRatings = ["G", "PG", "PG-13", "R", "NC-17"]
                if !validRatings.contains(ageRating) {
                    errors.append("Invalid age rating")
                }
            }
            
        case .music:
            // Validate music-specific fields
            if let artist = additionalFields["artist"] as? String {
                if validateAndSanitizeText(artist, maxLength: 200, fieldName: "artist") == nil {
                    errors.append("Artist name is invalid")
                }
            }
            
        case .event:
            // Validate event-specific fields
            if let startDate = additionalFields["eventStartDate"] as? Date {
                if !validateDate(startDate) {
                    errors.append("Event start date is out of valid range")
                }
            }
            
            if let location = additionalFields["eventLocation"] as? String {
                if validateAndSanitizeText(location, maxLength: 500, fieldName: "location") == nil {
                    errors.append("Event location is invalid")
                }
            }
            
        case .project:
            // Validate project-specific fields
            if let shootDates = additionalFields["shootDates"] as? String {
                if validateAndSanitizeText(shootDates, maxLength: 100, fieldName: "shootDates") == nil {
                    errors.append("Shoot dates are invalid")
                }
            }
            
        case .reel:
            // Validate reel-specific fields
            if let reelType = additionalFields["reelType"] as? String {
                let validTypes = ["Acting", "Cinematography", "Editing", "Directing", "Music/Sound", "Other"]
                if !validTypes.contains(reelType) {
                    errors.append("Invalid reel type")
                }
            }
        }
        
        return SubmissionValidationResult(isValid: errors.isEmpty, errors: errors)
    }
    
    // MARK: - File Upload Security
    
    /// Validate file before upload
    /// OWASP: File upload security
    struct FileValidationResult {
        let isValid: Bool
        let error: String?
    }
    
    func validateFileUpload(
        url: URL,
        allowedExtensions: [String],
        maxSizeBytes: Int64
    ) -> FileValidationResult {
        // Check file extension
        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            return FileValidationResult(
                isValid: false,
                error: "Invalid file type. Allowed: \(allowedExtensions.joined(separator: ", "))"
            )
        }
        
        // Check file size
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                guard fileSize <= maxSizeBytes else {
                    let sizeMB = Double(fileSize) / 1024 / 1024
                    let maxMB = Double(maxSizeBytes) / 1024 / 1024
                    return FileValidationResult(
                        isValid: false,
                        error: String(format: "File too large (%.1f MB). Max: %.1f MB", sizeMB, maxMB)
                    )
                }
            }
        } catch {
            return FileValidationResult(isValid: false, error: "Could not read file attributes")
        }
        
        return FileValidationResult(isValid: true, error: nil)
    }
    
    // MARK: - Audit Logging
    
    /// Log security events for monitoring
    /// OWASP: Implement logging and monitoring
    func logSecurityEvent(
        _ event: SecurityEvent,
        userID: String? = nil,
        details: [String: Any] = [:]
    ) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let user = userID ?? "anonymous"
        
        var logMessage = "🔒 SECURITY [\(timestamp)] \(event.rawValue) - User: \(user)"
        
        if !details.isEmpty {
            logMessage += " - Details: \(details)"
        }
        
        print(logMessage)
        
        // In production, send to centralized logging service
        // Example: Analytics, Crashlytics, custom logging server
        #if !DEBUG
        // sendToLoggingService(event, userID, details)
        #endif
    }
    
    enum SecurityEvent: String {
        case rateLimitExceeded = "RATE_LIMIT_EXCEEDED"
        case invalidInput = "INVALID_INPUT"
        case unauthorizedAccess = "UNAUTHORIZED_ACCESS"
        case suspiciousActivity = "SUSPICIOUS_ACTIVITY"
        case fileUploadRejected = "FILE_UPLOAD_REJECTED"
        case authenticationFailed = "AUTHENTICATION_FAILED"
        case dataIntegrityViolation = "DATA_INTEGRITY_VIOLATION"
    }
    
    // MARK: - Sensitive Data Protection
    
    /// Hash sensitive data before storing
    /// OWASP: Never store sensitive data in plain text
    func hashSensitiveData(_ data: String) -> String {
        let inputData = Data(data.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Validate password strength (if implementing password auth)
    /// OWASP: Enforce strong password policy
    func validatePasswordStrength(_ password: String) -> (isValid: Bool, message: String) {
        guard password.count >= 12 else {
            return (false, "Password must be at least 12 characters")
        }
        
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasNumber = password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecial = password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
        
        guard hasUppercase && hasLowercase && hasNumber && hasSpecial else {
            return (false, "Password must contain uppercase, lowercase, number, and special character")
        }
        
        return (true, "Password is strong")
    }
    
    // MARK: - Cleanup
    
    private var cleanupTimer: Timer?
    
    private init() {
        // Periodic cleanup of rate limit data
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.rateLimiter.cleanup()
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
}

// MARK: - Keychain Helper (Secure Storage)

/// Helper for securely storing sensitive data in Keychain
/// OWASP: Use platform-specific secure storage
class KeychainHelper {
    
    /// Save string value to keychain
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }
    
    /// Load string value from keychain
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    /// Delete value from keychain
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Security Constants

/// Security configuration constants
/// OWASP: Centralize security configuration
enum SecurityConstants {
    
    /// Maximum file sizes for uploads (OWASP: DoS prevention).
    /// Note: these are app-imposed ceilings, not CloudKit limits — CKAsset supports
    /// multi-GB files. Videos above this are transcoded down by VideoCompressionHelper.
    enum FileSizeLimits {
        static let video: Int64 = 5120 * 1024 * 1024  // 5 GB
        static let audio: Int64 = 1024 * 1024 * 1024  // 1 GB
        static let image: Int64 = 50 * 1024 * 1024    // 50 MB
    }
    
    /// Allowed file extensions (OWASP: File upload security)
    enum AllowedExtensions {
        static let video = ["mov", "mp4", "m4v", "mpeg4"]
        static let audio = ["mp3", "m4a", "aac", "wav", "aiff"]
        static let image = ["jpg", "jpeg", "png", "heic"]
    }
    
    /// Text field length limits (OWASP: Input validation)
    enum TextLengthLimits {
        static let title = 200
        static let shortText = 500
        static let longText = 5000
        static let url = 2048
    }
}
