//
//  ConversationDetailView.swift
//  Longhorn Artists Connect
//
//  Chat detail sheet for an existing NetworkView conversation.
//  Split out of NetworkView.swift to keep that file (and its preview) lightweight.
//

import SwiftUI
import UIKit
import PhotosUI

struct ConversationDetailView: View {
    let conversation: NetworkConversation
    @Environment(\.dismiss) private var dismiss
    
    @State private var messages: [NetworkMessage] = []
    @State private var newMessageText = ""
    @State private var isLoadingChat = true
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
            
            // Title with conversation name
            Text(conversation.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.bottom, 8)
            
            Divider()
            
            // Show loading indicator while chat loads
            if isLoadingChat {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading conversation...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Messages list
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
                                
                                if !message.isFromCurrentUser {
                                    Spacer()
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                Divider()
                
                // Message input
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
            }
        }
        .presentationDragIndicator(.hidden) // Hide default, we have custom
        .interactiveDismissDisabled(false) // Allow pull to dismiss
        .onAppear {
            loadMessages()
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
    
    private func loadMessages() {
        // Simulate loading delay using Swift Concurrency
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            isLoadingChat = false
            
            // Check if this is Test User
            if conversation.name == "Test User" {
                messages = [
                    NetworkMessage(text: "Hey! Welcome to Nexus messaging!", timestamp: Date(timeIntervalSinceNow: -600), isFromCurrentUser: false),
                    NetworkMessage(text: "I'm Test User, a practice conversation you can use to get familiar with the messaging interface.", timestamp: Date(timeIntervalSinceNow: -550), isFromCurrentUser: false),
                    NetworkMessage(text: "Feel free to send me any messages you want - this is just for practice!", timestamp: Date(timeIntervalSinceNow: -500), isFromCurrentUser: false)
                ]
            } else if conversation.name == "Owen Wilson" {
                messages = [
                    NetworkMessage(text: "Hey! I saw your latest film project on LAC. Really impressive work!", timestamp: Date(timeIntervalSinceNow: -7200), isFromCurrentUser: false),
                    NetworkMessage(text: "Thanks! That means a lot coming from you!", timestamp: Date(timeIntervalSinceNow: -7000), isFromCurrentUser: true),
                    NetworkMessage(text: "I'd love to collaborate on something sometime. Your cinematography style is really unique.", timestamp: Date(timeIntervalSinceNow: -6800), isFromCurrentUser: false),
                    NetworkMessage(text: "That would be incredible! I'm actually working on a new comedy short.", timestamp: Date(timeIntervalSinceNow: -4200), isFromCurrentUser: true),
                    NetworkMessage(text: conversation.lastMessage, timestamp: conversation.timestamp, isFromCurrentUser: false)
                ]
            } else if conversation.name == "Matthew McConaughey" {
                messages = [
                    NetworkMessage(text: "Just watched your reel - you've got some serious talent!", timestamp: Date(timeIntervalSinceNow: -172800), isFromCurrentUser: false),
                    NetworkMessage(text: "Wow, thank you so much! I really appreciate it 🙏", timestamp: Date(timeIntervalSinceNow: -172600), isFromCurrentUser: true),
                    NetworkMessage(text: "Keep pushing those creative boundaries. That's what it's all about.", timestamp: Date(timeIntervalSinceNow: -172400), isFromCurrentUser: false),
                    NetworkMessage(text: "Will do! Any advice for a student filmmaker?", timestamp: Date(timeIntervalSinceNow: -86800), isFromCurrentUser: true),
                    NetworkMessage(text: conversation.lastMessage, timestamp: conversation.timestamp, isFromCurrentUser: false)
                ]
            } else if conversation.name == "Test" {
                messages = [
                    NetworkMessage(text: "Hey! Welcome to LAC messaging!", timestamp: Date(timeIntervalSinceNow: -600), isFromCurrentUser: false),
                    NetworkMessage(text: "I'm Test, a practice conversation you can use to get familiar with the messaging interface.", timestamp: Date(timeIntervalSinceNow: -550), isFromCurrentUser: false),
                    NetworkMessage(text: "Feel free to send me any messages you want - this is just for practice!", timestamp: Date(timeIntervalSinceNow: -500), isFromCurrentUser: false),
                    NetworkMessage(text: conversation.lastMessage, timestamp: conversation.timestamp, isFromCurrentUser: false)
                ]
            } else {
                // Placeholder messages for other conversations
                messages = [
                    NetworkMessage(text: "Hey! How's your project coming along?", timestamp: Date(timeIntervalSinceNow: -3600), isFromCurrentUser: false),
                    NetworkMessage(text: "It's going great! Just finished editing the final scene.", timestamp: Date(timeIntervalSinceNow: -3500), isFromCurrentUser: true),
                    NetworkMessage(text: conversation.lastMessage, timestamp: conversation.timestamp, isFromCurrentUser: false)
                ]
            }
        }
    }
    
    private func sendMessage() {
        guard !newMessageText.isEmpty else { return }
        
        let message = NetworkMessage(
            text: newMessageText,
            timestamp: Date(),
            isFromCurrentUser: true
        )
        messages.append(message)
        newMessageText = ""
    }
}
