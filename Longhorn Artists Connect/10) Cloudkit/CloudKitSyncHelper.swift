//
//  CloudKitSyncHelper.swift
//  Longhorn Artists Connect
//
//  Helper for CloudKit syncing with pull-to-refresh
//

import SwiftUI

/// Add this to any view that displays submissions to enable pull-to-refresh sync
struct CloudKitSyncHelper: View {
    @ObservedObject var store: SubmissionStore_3_2
    @State private var isSyncing = false
    
    var body: some View {
        EmptyView()
            .refreshable {
                await refreshFromCloudKit()
            }
    }
    
    private func refreshFromCloudKit() async {
        guard !isSyncing else { return }
        isSyncing = true
        
        print("🔄 Manual refresh triggered...")
        await store.syncWithCloudKit()
        
        isSyncing = false
        print("✅ Manual refresh complete!")
    }
}

/// Extension to make it easy to add CloudKit sync to any List or ScrollView
extension View {
    func withCloudKitSync(store: SubmissionStore_3_2 = .shared) -> some View {
        self.refreshable {
            await store.forceSyncWithCloudKit()
        }
    }
}

/// A visible sync button you can add to navigation bars
struct CloudKitSyncButton: View {
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @State private var isSyncing = false
    @State private var showSuccess = false
    
    var body: some View {
        Button {
            Task {
                await sync()
            }
        } label: {
            if isSyncing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .brandOrange))
            } else if showSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.brandOrange)
            }
        }
        .disabled(isSyncing)
    }
    
    private func sync() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        await store.forceSyncWithCloudKit()
        isSyncing = false
        
        // Show success checkmark briefly
        showSuccess = true
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        showSuccess = false
    }
}

#Preview {
    CloudKitSyncButton()
}
