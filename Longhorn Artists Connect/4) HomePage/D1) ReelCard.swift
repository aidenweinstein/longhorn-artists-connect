//
//  ReelDetailView.swift
//  Longhorn Artists Connect
//
//  Detail view specifically for Reel (Talent) submissions
//

import SwiftUI
import AVKit

struct ReelDetailView: View {
    let reel: Submission
    @Binding var liked: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: SubmissionStore_3_2 = .shared

    @State private var selectedPortfolioName: CreditedPerson?
    @State private var showSendMessage = false
    @State private var showDeleteConfirmation = false
    @State private var showReportSheet = false
    @State private var showEditSheet = false
    @State private var showCollectionPicker = false
    
    // Icon color that adapts to light/dark mode
    private var iconColor: Color {
        colorScheme == .dark ? .white : .black
    }
    @State private var isLoading = true
    @State private var contentLoaded = false
    @State private var showFullScreenPoster = false
    
    private var canEditOrDelete: Bool {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == reel.submittedBy
        
        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let isAidenWeinstein = currentUser == "Aiden Weinstein"
        let canUseModerator = isModeratorMode && isAidenWeinstein
        
        return isUserCreator || canUseModerator
    }
    
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(reel.title.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        ZStack {
            if isLoading && !contentLoaded {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Video Player Section (Demo Reel)
                        VStack(alignment: .leading, spacing: 0) {
                            if let videoURL = reel.videoURL {
                                CustomVideoPlayerView(
                                    submission: reel,
                                    videoURL: videoURL,
                                    thumbnailData: reel.thumbnailData,
                                    tintColor: tintColor
                                )
                                .aspectRatio(16.0/9.0, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipped()
                            } else {
                                Button {
                                    showFullScreenPoster = true
                                } label: {
                                    ZStack {
                                        Rectangle()
                                            .fill(LinearGradient(
                                                colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(16.0/9.0, contentMode: .fit)
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 60, weight: .bold))
                                            .foregroundStyle(.white.opacity(0.9))
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .clipped()
                            }
                            
                            // Title and action buttons
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(reel.title)
                                            .font(.system(size: 28, weight: .bold))
                                            .minimumScaleFactor(0.6)
                                            .lineLimit(2)
                                        
                                        // Reel type
                                        if !reel.reelType.isEmpty {
                                            Text(reel.reelType)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Action buttons
                                    HStack(spacing: 6) { // Reduced from 12 to 6
                                        Button {
                                            store.toggleLike(for: reel)
                                        } label: {
                                            Image(systemName: store.isLiked(reel) ? "heart.fill" : "heart")
                                                .font(.system(size: 20))
                                                .foregroundStyle(store.isLiked(reel) ? .red : .primary)
                                                .frame(width: 32, height: 32)
                                        }
                                        
                                        Button {
                                            showCollectionPicker = true
                                        } label: {
                                            Image(systemName: store.isInAnyCollection(reel) ? "bookmark.fill" : "bookmark")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 32, height: 32)
                                        }
                                        
                                        Button {
                                            showSendMessage = true
                                        } label: {
                                            Image(systemName: "paperplane")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 32, height: 32)
                                        }
                                        
                                        Button {
                                            showReportSheet = true
                                        } label: {
                                            Image(systemName: "flag")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        }
                        
                        // Reel Information
                        VStack(alignment: .leading, spacing: 12) {
                            // Logline/Bio
                            if !reel.logline.isEmpty {
                                Text(reel.logline)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 12)
                            }
                            
                            // Moderator info
                            if UserDefaults.standard.bool(forKey: "isModeratorMode") {
                                let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
                                let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
                                let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
                                
                                if currentUser == "Aiden Weinstein" {
                                    Text("Submitted by \(reel.submittedBy)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal)
                                        .padding(.top, 16)
                                }
                            }
                            
                            // Edit and Delete buttons
                            if canEditOrDelete {
                                HStack(spacing: 12) {
                                    Button {
                                        showEditSheet = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "pencil")
                                            Text("Edit")
                                        }
                                        .font(.headline)
                                        .foregroundStyle(.orange)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.orange.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    
                                    Button {
                                        showDeleteConfirmation = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "trash")
                                            Text("Delete")
                                        }
                                        .font(.headline)
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.red.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.top, 24)
                                .padding(.bottom)
                            }
                        }
                        .padding()
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    isLoading = false
                    contentLoaded = true
                }
            }
        }
        .sheet(item: $selectedPortfolioName) { person in
            PersonProfileView(name: person.name)
        }
        .sheet(isPresented: $showSendMessage) {
            SendPostMessageView(post: reel)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentView(post: reel)
        }
        .sheet(isPresented: $showEditSheet) {
            ReelEditView(submission: reel) { updatedSubmission in
                store.update(updatedSubmission)
            }
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: reel)
        }
        .fullScreenCover(isPresented: $showFullScreenPoster) {
            FullScreenPosterView(post: reel, tintColor: tintColor)
        }
        .alert("Delete Reel?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                store.delete(reel)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

}

// Note: Video player components (CustomVideoPlayerView, FullScreenVideoPlayer, etc.) 
// are shared with FilmCard.swift and defined there.

#Preview {
    // Pretend a subset of the credited people already have Nexus accounts, so
    // those names render orange/clickable while the rest stay grey.
    let _ = UserDefaults.standard.set(
        ["Ava Thompson", "Priya Patel"],
        forKey: "createdUserProfiles"
    )
    return ReelDetailView(
        reel: Submission(
            id: UUID(),
            type: .reel,
            title: "Acting Reel",
            details: "Professional actor",
            logline: "Selected scenes from recent stage and screen work.",
            orderedCrew: [
                OrderedEntry(role: "Director", name: "Ava Thompson"),
                OrderedEntry(role: "Scene Partner", name: "Liam O'Brien"),
                OrderedEntry(role: "Editor", name: "Priya Patel")
            ],
            reelType: "Dramatic",
            reelExperience: "5 years of theater and independent film.",
            reelSpecificSkills: "Stage combat, dialects, improv"
        ),
        liked: .constant(false)
    )
}
