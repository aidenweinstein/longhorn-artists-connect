//
//  NetworkComposeViews.swift
//  Longhorn Artists Connect
//
//  Compose-side sheets for NetworkView: starting a new message, a brand-new
//  conversation, and the lightweight document-picker placeholder.
//  Split out of NetworkView.swift to keep that file (and its preview) lightweight.
//

import SwiftUI
import UIKit
import PhotosUI

// MARK: - New Message View

struct NewMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @ObservedObject var userProfileManager = UserProfileManager.shared
    @State private var searchText = ""
    @State private var messageText = ""
    @State private var selectedUser: String?
    
    // The user whose conversation is currently pushed on the navigation stack.
    @State private var selectedRecipient: DirectoryUser?

    // ✅ Get all CloudKit users (only users on Nexus)
    var registeredUsers: [DirectoryUser] {
        userProfileManager.allUsers
    }
    
    var filteredContacts: [DirectoryUser] {
        if searchText.isEmpty {
            return registeredUsers
        }
        return userProfileManager.searchUsers(searchText)
    }
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("New Message")
                .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible) // Standard indicator; header is a nav bar now
        .interactiveDismissDisabled(false) // Allow pull to dismiss
        .sheet(item: $selectedRecipient) { user in
            NavigationStack {
                InMessageView(
                    conversationID: existingConversationID(forOtherUser: user.id) ?? UUID(),
                    otherUserID: user.id,
                    otherUserName: user.fullName,
                    otherUserRole: user.rolesString
                )
            }
            .presentationDragIndicator(.visible)
        }
    }

    /// Returns the ID of an existing 1:1 conversation with the given user, if one
    /// is already loaded. Any conversation containing `otherUserID` as a participant
    /// is the thread with that user; nil means a fresh thread is created on first send.
    private func existingConversationID(forOtherUser otherUserID: String) -> UUID? {
        MessageStore.shared.conversations.first {
            $0.participant1UserID == otherUserID || $0.participant2UserID == otherUserID
        }?.id
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search users...", text: $searchText)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Contacts list - Apple style
            if userProfileManager.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .padding()
                    Text("Loading users...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredContacts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "person.2" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "No users found" : "No results found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if searchText.isEmpty {
                        Text("Users will appear here when they complete their profile")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("On Nexus") {
                        ForEach(filteredContacts) { user in
                            Button {
                                // Push the conversation for this recipient onto the stack.
                                selectedRecipient = user
                            } label: {
                                HStack(spacing: 12) {
                                    // Profile image or initials
                                    if let imageData = user.profileImageData,
                                       let uiImage = UIImage(data: imageData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 36, height: 36)
                                            .clipShape(Circle())
                                    } else {
                                        ZStack {
                                            Circle()
                                                .fill(Color.brandOrange.opacity(0.2))
                                                .frame(width: 36, height: 36)

                                            Text(user.initials)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Color.brandOrange)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.fullName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.primary)

                                        if !user.userTypes.isEmpty {
                                            Text(user.rolesString)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    if !user.graduationYear.isEmpty {
                                        Text("'\(String(user.graduationYear.suffix(2)))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .refreshable {
            await userProfileManager.fetchAllUsers(forceRefresh: true)
        }
    }
}

// MARK: - New Conversation View (Apple Messages-like)

struct NewConversationView: View {
    let recipientName: String
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [NetworkMessage] = []
    @State private var newMessageText = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDocumentPicker = false
    @State private var showSavedPosts = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            // Title with recipient name
            Text(recipientName)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.bottom, 8)
            
            Divider()
            
            // Empty state helper text when no messages
            if messages.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.brandOrange.opacity(0.3))
                    
                    Text("Start a conversation with \(recipientName)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("Send a message to get started")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    
                    Spacer()
                }
                .padding()
            } else {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(messages) { message in
                                HStack {
                                    if message.isFromCurrentUser {
                                        Spacer()
                                    }
                                    
                                    VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                                        Text(message.text)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .fill(message.isFromCurrentUser ? Color.brandOrange : Color.secondary.opacity(0.15))
                                            )
                                            .foregroundStyle(message.isFromCurrentUser ? .white : .primary)
                                        
                                        Text(message.timestamp, style: .time)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .id(message.id)
                                    
                                    if !message.isFromCurrentUser {
                                        Spacer()
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: messages.count) { _, _ in
                        // Scroll to bottom when new message is added
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Message input - Apple Messages style
            HStack(spacing: 12) {
                // Attachment button with compact menu
                Menu {
                    Button {
                        showPhotosPicker = true
                    } label: {
                        Label("Photos", systemImage: "photo")
                    }
                    
                    Button {
                        showDocumentPicker = true
                    } label: {
                        Label("File", systemImage: "doc")
                    }
                    
                    Button {
                        showSavedPosts = true
                    } label: {
                        Label("Saved Post", systemImage: "bookmark")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.brandOrange)
                }
                .menuStyle(.button)
                .menuOrder(.fixed)
                
                TextField("Message", text: $newMessageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .focused($isTextFieldFocused)
                    .lineLimit(1...5)
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(newMessageText.isEmpty ? .secondary : Color.brandOrange)
                }
                .disabled(newMessageText.isEmpty)
            }
            .padding()
            .background(Color(uiColor: .systemBackground))
        }
        .presentationDragIndicator(.hidden) // Hide default, we have custom
        .interactiveDismissDisabled(false) // Allow pull to dismiss
        .onAppear {
            print("📱 Opening conversation with: \(recipientName)")
            
            // Load pre-existing messages for Test User
            if recipientName == "Test User" {
                messages = [
                    NetworkMessage(text: "Hey! Welcome to Nexus messaging!", timestamp: Date(timeIntervalSinceNow: -600), isFromCurrentUser: false),
                    NetworkMessage(text: "I'm Test User, a practice conversation you can use to get familiar with the messaging interface.", timestamp: Date(timeIntervalSinceNow: -550), isFromCurrentUser: false),
                    NetworkMessage(text: "Feel free to send me any messages you want - this is just for practice!", timestamp: Date(timeIntervalSinceNow: -500), isFromCurrentUser: false)
                ]
            }
            
            // Auto-focus the text field using Swift Concurrency
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                isTextFieldFocused = true
            }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotoItem, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            if newValue != nil {
                // Handle selected photo/video
                print("📸 Photo/Video selected: \(newValue?.itemIdentifier ?? "unknown")")
                // TODO: Send the photo/video in a message
                selectedPhotoItem = nil
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            NetworkDocumentPicker()
        }
        .sheet(isPresented: $showSavedPosts) {
            SavedPostsPickerView()
        }
    }
    
    private func sendMessage() {
        guard !newMessageText.isEmpty else { return }
        
        print("📤 Sending message to \(recipientName): \(newMessageText)")
        
        let message = NetworkMessage(
            text: newMessageText,
            timestamp: Date(),
            isFromCurrentUser: true
        )
        messages.append(message)
        newMessageText = ""
    }
}

// MARK: - Network Document Picker View

struct NetworkDocumentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.brandOrange)
                
                Text("Select a File")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose a file to send in your message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Send File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
// MARK: - Previews

#Preview("New Message") {
    NewMessageView()
}

#Preview("New Conversation") {
    NewConversationView(recipientName: "Jane Smith")
}

#Preview("Document Picker") {
    NetworkDocumentPickerView()
}

