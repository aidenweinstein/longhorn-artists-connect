# Security Implementation Guide
## Longhorn Artists Connect - OWASP Compliant Security

This document outlines the security measures implemented in the Longhorn Artists Connect app, following OWASP best practices for mobile application security.

---

## 🔒 Overview

This app implements defense-in-depth security with:
- **Rate Limiting**: IP + user-based protection against abuse
- **Input Validation**: Schema-based validation with type checks and length limits
- **Secure Data Handling**: Encrypted storage, secure API key management
- **Audit Logging**: Security event monitoring and alerting
- **File Upload Security**: Type validation, size limits, malware prevention

---

## 📋 Table of Contents

1. [Rate Limiting](#rate-limiting)
2. [Input Validation & Sanitization](#input-validation--sanitization)
3. [API Key Management](#api-key-management)
4. [Data Protection](#data-protection)
5. [CloudKit Security](#cloudkit-security)
6. [Audit Logging](#audit-logging)
7. [Production Checklist](#production-checklist)

---

## 1. Rate Limiting

### Implementation
**File**: `SecurityManager.swift`

### Rate Limit Configurations

| Operation | Max Requests | Time Window | Purpose |
|-----------|--------------|-------------|---------|
| **CloudKit Writes** | 10 | 60s | Prevent spam submissions |
| **CloudKit Reads** | 100 | 60s | Prevent DoS on queries |
| **Messages** | 20 | 60s | Prevent message spam |
| **Authentication** | 5 | 300s | Prevent brute force |

### Usage Example

```swift
// Check rate limit before submission
guard SecurityManager.shared.checkWriteRateLimit(userID: userID) else {
    // Show error: "Too many submissions. Please wait."
    return
}

// Proceed with submission
```

### How It Works

1. **Device Identifier**: Uses persistent device ID stored in Keychain
2. **User Identifier**: Uses CloudKit user record ID when available
3. **Sliding Window**: Tracks timestamps in rolling time windows
4. **Graceful Degradation**: Returns 429-style errors with clear messages
5. **Auto-Cleanup**: Periodically removes old timestamps

### Benefits

- ✅ Prevents DoS attacks
- ✅ Prevents spam submissions
- ✅ Prevents brute force attacks
- ✅ Fair usage for all users
- ✅ Protects CloudKit quota

---

## 2. Input Validation & Sanitization

### Implementation
**File**: `SecurityManager.swift` - `validateSubmission()`, `validateAndSanitizeText()`

### Validation Rules

#### Text Fields

```swift
// Title validation
- Max length: 200 characters
- Allowed characters: [\\w\\s\\-.,!?'\"()&]+
- XSS protection: Remove <script>, javascript:
- Required: Non-empty

// Details/Description
- Max length: 5000 characters
- XSS protection enabled
- Required: Non-empty

// URLs
- Validate format
- Allowed schemes: http, https
- Max length: 2048 characters
```

#### Type-Specific Validation

**Films:**
- Age Rating: Must be G, PG, PG-13, R, or NC-17
- Studio: Max 200 characters
- Genres: Validated against whitelist

**Music:**
- Artist: Max 200 characters
- Streaming Links: Valid URL format

**Events:**
- Location: Max 500 characters, geocoding validation
- Dates: Within reasonable range (-5 to +10 years)

**Projects:**
- Shoot Dates: Max 100 characters
- Cast/Crew Needed: Array validation

**Reels:**
- Reel Type: Validated against whitelist
- Experience: Max 500 characters

### File Upload Validation

```swift
// Video files
- Allowed extensions: mov, mp4, m4v, mpeg4
- Max size: 5 GB
- Automatic compression if needed

// Audio files
- Allowed extensions: mp3, m4a, aac, wav, aiff
- Max size: 1 GB

// Image files
- Allowed extensions: jpg, jpeg, png, heic
- Max size: 50 MB
```

### Usage Example

```swift
// Validate submission data
let validationResult = SecurityManager.shared.validateSubmission(
    title: title,
    details: details,
    type: .film,
    additionalFields: [
        "ageRating": ageRating,
        "eventStartDate": startDate
    ]
)

guard validationResult.isValid else {
    // Show errors: validationResult.errors
    return
}
```

### XSS Prevention

The following patterns are automatically removed:
- `<script>` tags (case-insensitive)
- `javascript:` protocol
- Other potentially dangerous patterns

### Benefits

- ✅ Prevents XSS attacks
- ✅ Prevents SQL injection (CloudKit uses NoSQL)
- ✅ Prevents buffer overflow attacks
- ✅ Ensures data integrity
- ✅ Prevents malformed data

---

## 3. API Key Management

### Implementation
**File**: `SecurityConfiguration.swift`

### ⚠️ CRITICAL: API Key Security

**NEVER commit API keys to source control!**

### Best Practices

#### 1. Environment Variables

```swift
// Load from environment
static var apiKey: String {
    guard let key = ProcessInfo.processInfo.environment["API_KEY"] else {
        fatalError("API_KEY not set")
    }
    return key
}
```

**Set in Xcode:**
1. Edit Scheme → Run → Arguments
2. Add Environment Variables
3. Name: `API_KEY`, Value: `your-key-here`

#### 2. Keychain Storage

```swift
// Store securely
SecurityConfiguration.storeAPIKey("your-key", identifier: "service-name")

// Retrieve securely
let key = SecurityConfiguration.retrieveAPIKey(identifier: "service-name")
```

#### 3. Separate Files (Excluded from Git)

Create `SecurityConfiguration-Local.swift`:

```swift
extension SecureConfiguration {
    static var localAPIKey: String {
        return "dev-key-here"
    }
}
```

Add to `.gitignore`:

```gitignore
# Security Configuration
SecurityConfiguration-Local.swift
*.plist containing "API"
*.xcconfig containing secrets
```

### Key Rotation

Implemented automatic key rotation policy:

```swift
// Check if rotation needed (every 90 days)
if SecurityConfiguration.shouldRotateKeys() {
    try await SecurityConfiguration.rotateKeys()
}
```

### CloudKit Container ID

The CloudKit container ID is **public information** and can be in source code:

```swift
static let cloudKitContainerID = "iCloud.LAA.Longhorn-Artists-Connect"
```

This is not a secret and is required for CloudKit to work.

---

## 4. Data Protection

### Keychain Usage

**File**: `SecurityManager.swift` - `KeychainHelper` class

All sensitive data is stored in iOS Keychain with:
- **Access Level**: `kSecAttrAccessibleAfterFirstUnlock`
- **Encryption**: Hardware-encrypted by iOS
- **Persistence**: Survives app reinstall (unless user deletes app data)

### What's Stored in Keychain

```swift
// Device identifier (for rate limiting)
KeychainHelper.save(key: "deviceID", value: deviceID)

// API keys (if needed)
KeychainHelper.save(key: "api_key_service", value: apiKey)
```

### Data Protection Levels

| Data Type | Protection | Storage |
|-----------|------------|---------|
| User passwords | Hashed (SHA256) | Keychain |
| Device ID | Plain | Keychain |
| API keys | Plain | Keychain |
| User content | Plain | CloudKit |
| Local files | File Protection | Documents |

### Sensitive Data Hashing

```swift
// Hash sensitive data before storage
let hashedPassword = SecurityManager.shared.hashSensitiveData(password)
```

Uses SHA256 for one-way hashing.

---

## 5. CloudKit Security

### CloudKit Security Model

CloudKit provides built-in security:

1. **Authentication**: User must be signed into iCloud
2. **Authorization**: CloudKit permissions control access
3. **Data Privacy**: User data is encrypted by Apple
4. **Rate Limiting**: Apple enforces CloudKit quotas

### Our Additional Security Layers

1. **Client-Side Rate Limiting**: Prevent quota exhaustion
2. **Input Validation**: Before sending to CloudKit
3. **File Size Limits**: Prevent large uploads
4. **User Authorization**: Check permissions before operations

### CloudKit Permissions

**Public Database** (Current Setup):
- Anyone can read
- Only authenticated users can write
- Users can only modify their own records

**Best Practice**: Use CloudKit Dashboard to set additional permissions:
1. Go to CloudKit Dashboard
2. Select Security Roles
3. Configure permissions per record type

### Schema Validation

All CloudKit records are validated:
- Field types match schema
- Required fields present
- Field lengths within limits
- Dates in valid ranges

---

## 6. Audit Logging

### Implementation
**File**: `SecurityManager.swift` - `logSecurityEvent()`

### Logged Security Events

```swift
enum SecurityEvent {
    case rateLimitExceeded       // User hit rate limit
    case invalidInput            // Input validation failed
    case unauthorizedAccess      // Permission denied
    case suspiciousActivity      // Unusual patterns detected
    case fileUploadRejected      // File validation failed
    case authenticationFailed    // Login attempt failed
    case dataIntegrityViolation  // Data corruption detected
}
```

### Log Format

```
🔒 SECURITY [2025-02-25T10:30:00Z] RATE_LIMIT_EXCEEDED - User: ABC123 - Details: {"action": "submission"}
```

### Usage Example

```swift
SecurityManager.shared.logSecurityEvent(
    .rateLimitExceeded,
    userID: userID,
    details: ["action": "message", "count": 25]
)
```

### Log Destinations

**Debug Build:**
- Console output only

**Production Build:**
- Console output
- Centralized logging service (implement `sendToLoggingService()`)
- Analytics service (e.g., Firebase Analytics)
- Crash reporting (e.g., Crashlytics)

### Privacy Considerations

**Never log:**
- Passwords (even hashed)
- Full API keys
- Personal messages content
- Credit card numbers
- Social security numbers

**Safe to log:**
- User IDs (hashed)
- Event types
- Timestamps
- Action types
- Error codes

---

## 7. Production Checklist

### Pre-Launch Security Audit

#### API Keys & Secrets ✅
- [ ] No hardcoded API keys in source code
- [ ] All secrets loaded from environment variables
- [ ] Keychain used for sensitive data storage
- [ ] Key rotation policy implemented (90 days)
- [ ] Different keys for dev/staging/production
- [ ] `.gitignore` excludes secret files

#### Network Security ✅
- [ ] HTTPS enforced for all connections
- [ ] Certificate pinning implemented (if using external APIs)
- [ ] Domain whitelist configured
- [ ] Security headers set on requests
- [ ] CloudKit permissions properly configured

#### Input Validation ✅
- [ ] All user inputs validated
- [ ] Length limits enforced
- [ ] Type checking implemented
- [ ] XSS prevention active
- [ ] File upload validation working

#### Rate Limiting ✅
- [ ] Rate limits configured for all operations
- [ ] User-based rate limiting active
- [ ] Device-based rate limiting active
- [ ] Graceful error handling (429 responses)
- [ ] Rate limit cleanup running

#### Data Protection ✅
- [ ] Keychain used for sensitive data
- [ ] File protection enabled
- [ ] Sensitive data hashed before storage
- [ ] Secure deletion implemented
- [ ] Data encrypted at rest (CloudKit)

#### Logging & Monitoring ✅
- [ ] Security events logged
- [ ] Sensitive data never logged
- [ ] Centralized logging configured
- [ ] Alerting set up for critical events
- [ ] Log retention policy defined

#### Code Quality ✅
- [ ] All security functions tested
- [ ] Edge cases handled
- [ ] Error handling comprehensive
- [ ] Dependencies up to date
- [ ] Security advisories reviewed

#### App Store Requirements ✅
- [ ] Privacy policy updated
- [ ] Data collection disclosed
- [ ] Third-party SDKs listed
- [ ] Encryption export compliance
- [ ] App Transport Security enabled

---

## 🚀 Quick Start

### For Developers

1. **Clone the repo** (never commit secrets!)

2. **Set up environment variables:**
   ```bash
   # Add to Xcode scheme
   # Edit Scheme → Run → Arguments → Environment Variables
   API_KEY=your-dev-key-here
   ```

3. **Create local config** (excluded from git):
   ```bash
   cp SecurityConfiguration.swift SecurityConfiguration-Local.swift
   # Edit SecurityConfiguration-Local.swift with your keys
   ```

4. **Add to `.gitignore`:**
   ```gitignore
   SecurityConfiguration-Local.swift
   ```

5. **Test security:**
   ```swift
   // Run security validation
   let result = SecurityManager.shared.validateSubmission(...)
   guard result.isValid else { /* handle errors */ }
   ```

### For Production

1. **Set production environment variables**
2. **Configure CloudKit permissions**
3. **Enable crash reporting**
4. **Set up monitoring alerts**
5. **Rotate API keys**
6. **Test rate limiting**
7. **Run security audit**

---

## 📞 Security Contact

For security issues, contact:
- **Email**: security@example.com (⚠️ Update this!)
- **Response Time**: 24 hours
- **Disclosure Policy**: 90 days

---

## 📚 Resources

### OWASP Mobile Security
- [OWASP Mobile Security Project](https://owasp.org/www-project-mobile-security/)
- [OWASP Mobile Top 10](https://owasp.org/www-project-mobile-top-10/)
- [OWASP MASVS](https://github.com/OWASP/owasp-masvs)

### Apple Security
- [iOS Security Guide](https://support.apple.com/guide/security/welcome/web)
- [App Security Best Practices](https://developer.apple.com/documentation/security)
- [CloudKit Security](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitQuickStart/EnablingiCloudandConfiguringCloudKit/EnablingiCloudandConfiguringCloudKit.html)

### Tools
- [OWASP ZAP](https://www.zaproxy.org/) - Security testing
- [MobSF](https://github.com/MobSF/Mobile-Security-Framework-MobSF) - Mobile security framework
- [Checkmarx](https://www.checkmarx.com/) - Static analysis

---

## 🔄 Updates

### Version History

- **v1.0** (2025-02-25): Initial security implementation
  - Rate limiting added
  - Input validation implemented
  - API key management configured
  - Audit logging enabled
  - Documentation created

### Planned Enhancements

- [ ] Biometric authentication
- [ ] End-to-end encryption for messages
- [ ] Advanced threat detection
- [ ] Automated security testing
- [ ] Penetration testing

---

## ✅ Compliance

This implementation follows:

- ✅ **OWASP Mobile Top 10** (2024)
- ✅ **OWASP ASVS** (Application Security Verification Standard)
- ✅ **Apple App Store Review Guidelines** (Security section)
- ✅ **GDPR** (General Data Protection Regulation) - EU
- ✅ **CCPA** (California Consumer Privacy Act) - US

---

## 📝 License

Security implementations are part of the Longhorn Artists Connect app and follow the same license as the main application.

---

**Last Updated**: February 25, 2025
**Version**: 1.0
**Maintainer**: Development Team
