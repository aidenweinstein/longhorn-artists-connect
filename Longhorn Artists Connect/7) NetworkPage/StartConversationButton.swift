//
//  StartConversationButton.swift
//  Longhorn Artists Connect
//
//  Reusable button component for starting conversations from user profiles
//

import SwiftUI
import CloudKit

struct StartConversationButton: View {
    let recipientUserID: String
    let recipientName: String
    let recipientRole: String
    
    @State private var showMessageView = false
    @State private var conversationID: UUID?
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Button {
            startConversation()
        } label: {
            HStack {
                Image(systemName: "message.fill")
                Text("Message")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.brandOrange)
            .foregroundStyle(.white)
            .fontWeight(.semibold)
            .cornerRadius(12)
        }
        .disabled(isLoading)
        .overlay {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        .sheet(isPresented: $showMessageView) {
            if let conversationID = conversationID {
                NavigationStack {
                    InMessageView(
                        conversationID: conversationID,
                        otherUserID: recipientUserID,
                        otherUserName: recipientName,
                        otherUserRole: recipientRole
                    )
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func startConversation() {
        isLoading = true
        
        Task {
            defer {
                Task { @MainActor in
                    isLoading = false
                }
            }
            
            do {
                // Get current user ID
                let currentUserID = try await CKContainer.default().userRecordID().recordName
                
                // Check if conversation already exists
                try await MessageStore.shared.fetchConversations()
                
                let existingConversation = MessageStore.shared.conversations.first { conversation in
                    (conversation.participant1UserID == currentUserID && conversation.participant2UserID == recipientUserID) ||
                    (conversation.participant1UserID == recipientUserID && conversation.participant2UserID == currentUserID)
                }
                
                await MainActor.run {
                    if let existing = existingConversation {
                        conversationID = existing.id
                    } else {
                        conversationID = UUID()
                    }
                    showMessageView = true
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to start conversation: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

// MARK: - Compact Style

struct CompactMessageButton: View {
    let recipientUserID: String
    let recipientName: String
    let recipientRole: String
    
    @State private var showMessageView = false
    @State private var conversationID: UUID?
    @State private var isLoading = false
    
    var body: some View {
        Button {
            startConversation()
        } label: {
            Image(systemName: "message.fill")
                .font(.body)
                .foregroundStyle(Color.brandOrange)
        }
        .disabled(isLoading)
        .sheet(isPresented: $showMessageView) {
            if let conversationID = conversationID {
                NavigationStack {
                    InMessageView(
                        conversationID: conversationID,
                        otherUserID: recipientUserID,
                        otherUserName: recipientName,
                        otherUserRole: recipientRole
                    )
                }
            }
        }
    }
    
    private func startConversation() {
        isLoading = true
        
        Task {
            defer {
                Task { @MainActor in
                    isLoading = false
                }
            }
            
            do {
                let currentUserID = try await CKContainer.default().userRecordID().recordName
                try await MessageStore.shared.fetchConversations()
                
                let existingConversation = MessageStore.shared.conversations.first { conversation in
                    (conversation.participant1UserID == currentUserID && conversation.participant2UserID == recipientUserID) ||
                    (conversation.participant1UserID == recipientUserID && conversation.participant2UserID == currentUserID)
                }
                
                await MainActor.run {
                    conversationID = existingConversation?.id ?? UUID()
                    showMessageView = true
                }
                
            } catch {
                print("⚠️ Failed to start conversation: \(error)")
            }
        }
    }
}

// MARK: - Usage Examples

/*
 
 ## Full Width Button (for profile pages)
 
 ```swift
 VStack {
     // User profile info
     Text(userName)
         .font(.title)
     Text(userRole)
         .font(.subheadline)
     
     // Message button
     StartConversationButton(
         recipientUserID: user.cloudKitRecordID,
         recipientName: user.name,
         recipientRole: user.role
     )
     .padding()
 }
 ```
 
 ## Compact Button (for cards or lists)
 
 ```swift
 HStack {
     Text(userName)
     Spacer()
     CompactMessageButton(
         recipientUserID: user.cloudKitRecordID,
         recipientName: user.name,
         recipientRole: user.role
     )
 }
 ```
 
 ## In a Toolbar
 
 ```swift
 .toolbar {
     ToolbarItem(placement: .topBarTrailing) {
         CompactMessageButton(
             recipientUserID: user.cloudKitRecordID,
             recipientName: user.name,
             recipientRole: user.role
         )
     }
 }
 ```
 
 */

// MARK: - Preview

#Preview("Full Width Button") {
    VStack {
        Spacer()
        
        StartConversationButton(
            recipientUserID: "mockUserID",
            recipientName: "Sarah Johnson",
            recipientRole: "Director"
        )
        .padding()
        
        Spacer()
    }
}

#Preview("Compact Button") {
    HStack {
        Text("Sarah Johnson")
            .font(.headline)
        Spacer()
        CompactMessageButton(
            recipientUserID: "mockUserID",
            recipientName: "Sarah Johnson",
            recipientRole: "Director"
        )
    }
    .padding()
}
