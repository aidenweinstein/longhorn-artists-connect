//
//  CloudKitConfiguration.swift
//  Longhorn Artists Connect
//
//  Utilities for switching between real and mock CloudKit
//

import Foundation

/// Configuration for CloudKit testing
enum CloudKitConfiguration {
    /// Whether to use mock CloudKit manager
    static var useMockManager: Bool {
        #if DEBUG
        // Check environment variable (set in scheme)
        if ProcessInfo.processInfo.environment["USE_MOCK_CLOUDKIT"] == "1" {
            return true
        }
        
        // Check UserDefaults (can be toggled in Settings during development)
        if UserDefaults.standard.bool(forKey: "UseMockCloudKit") {
            return true
        }
        
        // By default, use real CloudKit in DEBUG builds too
        return false
        #else
        // Always use real CloudKit in release builds
        return false
        #endif
    }
    
    /// Get the appropriate CloudKit manager (real or mock)
    @MainActor
    static var manager: any CloudKitManagerProtocol {
        #if DEBUG
        if useMockManager {
            print("🎭 Using MockCloudKitManager")
            return MockCloudKitManager.shared
        }
        #endif
        
        print("☁️ Using real CloudKitManager")
        return CloudKitManager.shared
    }
    
    /// Enable mock mode (useful for debugging)
    static func enableMockMode() {
        #if DEBUG
        UserDefaults.standard.set(true, forKey: "UseMockCloudKit")
        print("🎭 Mock CloudKit mode enabled")
        #endif
    }
    
    /// Disable mock mode
    static func disableMockMode() {
        #if DEBUG
        UserDefaults.standard.set(false, forKey: "UseMockCloudKit")
        print("☁️ Real CloudKit mode enabled")
        #endif
    }
}

#if DEBUG
// MARK: - Development Settings View

import SwiftUI

/// A settings view for toggling CloudKit mode during development
struct DeveloperSettingsView: View {
    @State private var useMockCloudKit = CloudKitConfiguration.useMockManager
    @State private var showRestartAlert = false
    
    var body: some View {
        Form {
            Section("CloudKit Configuration") {
                Toggle("Use Mock CloudKit", isOn: $useMockCloudKit)
                    .onChange(of: useMockCloudKit) { _, newValue in
                        if newValue {
                            CloudKitConfiguration.enableMockMode()
                        } else {
                            CloudKitConfiguration.disableMockMode()
                        }
                        showRestartAlert = true
                    }
                
                Text("Mock CloudKit uses simulated data and doesn't require an iCloud account. Useful for testing UI without network calls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Current Status") {
                HStack {
                    Text("Mode")
                    Spacer()
                    Text(CloudKitConfiguration.useMockManager ? "Mock" : "Real CloudKit")
                        .foregroundStyle(.secondary)
                }
                
                Text("Changes require app restart to take effect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Actions") {
                Button("Reset Mock Data") {
                    MockCloudKitManager.shared.resetMockData()
                }
                .disabled(!CloudKitConfiguration.useMockManager)
                
                Button("Clear Mock Data") {
                    MockCloudKitManager.shared.clearMockData()
                }
                .disabled(!CloudKitConfiguration.useMockManager)
            }
        }
        .navigationTitle("Developer Settings")
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("OK") { }
        } message: {
            Text("Please restart the app for changes to take effect")
        }
    }
}

#Preview("Developer Settings") {
    NavigationStack {
        DeveloperSettingsView()
    }
}

#endif
