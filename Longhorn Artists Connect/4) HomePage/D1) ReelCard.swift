//
//  ReelDetailView.swift
//  Longhorn Artists Connect
//
//  Detail view specifically for Reel (Talent) submissions
//

import SwiftUI
import AVKit

struct ReelDetailView: View {
    /// The reel as originally passed in. Display reads go through `reel` (below), which
    /// resolves the current version from the store so an edit is reflected immediately.
    private let passedReel: Submission
    @Binding var liked: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: SubmissionStore_3_2 = .shared

    /// The live version of this reel from the store (falling back to the passed-in copy),
    /// so edits to the description/type/thumbnail appear without reopening the detail.
    private var reel: Submission {
        store.approvedSubmissions.first { $0.id == passedReel.id }
            ?? store.submissions.first { $0.id == passedReel.id }
            ?? passedReel
    }

    init(reel: Submission, liked: Binding<Bool>) {
        self.passedReel = reel
        self._liked = liked
    }

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
    /// Shown only once loading has run for over 1.5s (first-launch content download).
    @State private var showSlowLoadingMessage = false
    /// The resolved local video file. The feed no longer downloads video assets, so
    /// this is filled from a cached copy or an on-demand fetch when the reel opens.
    @State private var resolvedVideoURL: URL?
    @State private var isLoadingVideo = false
    /// True once `resolveVideo()` finished and found no playable video — shows a
    /// non-tappable "Coming Soon" instead of a poster that would softlock the view.
    @State private var noVideoAvailable = false
    /// Bumped after an edit replaces the video so the inline player is recreated (the new
    /// file is written to the same path, so the AVPlayer won't reload it on its own).
    @State private var videoReloadToken = 0
    /// A featured-work post the user tapped, presented in its own detail sheet.
    @State private var selectedFeaturedWork: Submission?
    @State private var featuredLiked = false
    
    private var canEditOrDelete: Bool {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == reel.submittedBy
        
        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let canUseModerator = isModeratorMode && ModeratorAccess.isModerator

        return isUserCreator || canUseModerator
    }
    
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(reel.title.hashValue)
        return colors[hash % colors.count]
    }

    /// The reel's featured-work posts, resolved from their stored IDs against the store.
    private var featuredWorks: [Submission] {
        let all = store.approvedSubmissions + store.submissions
        return reel.featuredWorkIDs.compactMap { idString in
            guard let uuid = UUID(uuidString: idString) else { return nil }
            return all.first { $0.id == uuid }
        }
    }

    /// Hand-typed featured-work entries (project + director) that aren't posts on the app.
    private var manualFeaturedWorks: [ManualFeaturedWork] {
        reel.featuredWorkManual.compactMap(ManualFeaturedWork.init(encoded:))
    }

    /// Resolves the playable video. Uses the uploader's local copy if one is already on
    /// disk; otherwise streams from a range-supporting CDN URL. The video is never
    /// downloaded to the device — if no streaming URL is available, the "Coming Soon"
    /// placeholder is shown instead of a full download.
    private func resolveVideo() async {
        if let local = reel.videoURL {
            if await FilmDetailView.hasVideoTrack(local) {
                resolvedVideoURL = local
            } else {
                noVideoAvailable = true
            }
            return
        }
        guard resolvedVideoURL == nil, !isLoadingVideo else { return }
        isLoadingVideo = true
        // Stream only: play from a range-supporting CDN URL so playback starts without
        // ever writing the file to the device. If no streaming URL is available (e.g.
        // web services not configured / lookup failed), show the placeholder rather than
        // falling back to a full local download.
        if let streamURL = await CloudKitManager.shared.streamingURL(submissionID: reel.id, type: .reel) {
            resolvedVideoURL = streamURL
        } else {
            noVideoAvailable = true
        }
        isLoadingVideo = false
    }

    /// Shown when a reel has no video attached — a non-tappable placeholder (tapping the
    /// old poster opened a full-screen thumbnail with no way back, softlocking the view).
    private var comingSoonPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(
                    colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            VStack(spacing: 10) {
                Image(systemName: "video.slash")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Coming Soon")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0/9.0, contentMode: .fit)
        .clipped()
    }

    // MARK: - Featured Work

    /// Presents the appropriate detail view for a tapped featured-work post.
    @ViewBuilder
    private func featuredWorkDetail(for work: Submission) -> some View {
        switch work.type {
        case .film, .music, .reel, .photography:
            PostDetailRouter(post: work, liked: $featuredLiked)
        case .project:
            UpcomingProjectDetailView(submission: work)
        case .event:
            EventDetailView(event: work)
        }
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

                    if showSlowLoadingMessage {
                        Text("When first downloading Nexus, content may take a few minutes to load. But, from there on after, it will be quick!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    // Only surface the first-launch hint if loading is still going after 1.5s.
                    // SwiftUI cancels this task when content loads and the view is removed.
                    try? await Task.sleep(for: .seconds(1.5))
                    showSlowLoadingMessage = true
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Video Player Section (Demo Reel)
                        VStack(alignment: .leading, spacing: 0) {
                            if let videoURL = resolvedVideoURL {
                                CustomVideoPlayerView(
                                    submission: reel,
                                    videoURL: videoURL,
                                    thumbnailData: reel.thumbnailData,
                                    tintColor: tintColor
                                )
                                // Recreate the player after an edit replaces the video.
                                .id(videoReloadToken)
                                .aspectRatio(16.0/9.0, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipped()
                            } else if noVideoAvailable {
                                // No video attached — non-tappable placeholder (the old
                                // poster opened a full-screen thumbnail that softlocked).
                                comingSoonPlaceholder
                            } else {
                                // Still resolving: spinner while the on-demand download runs.
                                ZStack {
                                    Rectangle()
                                        .fill(LinearGradient(
                                            colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        .frame(maxWidth: .infinity)
                                        .aspectRatio(16.0/9.0, contentMode: .fit)
                                    ProgressView()
                                        .tint(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .task { await resolveVideo() }
                            }
                            
                            // Title and action buttons
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(reel.title)
                                            .font(.system(size: 28, weight: .bold))
                                            .minimumScaleFactor(0.6)
                                            .lineLimit(2)

                                        // Artist name — same placement/style as the music card.
                                        if !reel.artist.isEmpty {
                                            Text(reel.artist)
                                                .font(.title3)
                                                .foregroundStyle(.secondary)
                                        }

                                        // Reel type
                                        if !reel.reelType.isEmpty {
                                            Text(reel.reelType)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Action buttons — packed tight to leave the title more room.
                                    HStack(spacing: 2) {
                                        Button {
                                            store.toggleLike(for: reel)
                                        } label: {
                                            // Like counts are private: only credited collaborators
                                            // see them on their own portfolio page.
                                            Image(systemName: store.isLiked(reel) ? "heart.fill" : "heart")
                                                .font(.system(size: 20))
                                                .foregroundStyle(store.isLiked(reel) ? .red : .primary)
                                                .frame(minWidth: 30, minHeight: 32)
                                        }

                                        Button {
                                            showCollectionPicker = true
                                        } label: {
                                            Image(systemName: store.isInAnyCollection(reel) ? "bookmark.fill" : "bookmark")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 30, height: 32)
                                        }

                                        Button {
                                            showSendMessage = true
                                        } label: {
                                            Image(systemName: "paperplane")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 30, height: 32)
                                        }

                                        Button {
                                            showReportSheet = true
                                        } label: {
                                            Image(systemName: "flag")
                                                .font(.system(size: 20))
                                                .foregroundStyle(iconColor)
                                                .frame(width: 30, height: 32)
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
                            // Description (the reel's own "reelDescription" field, which
                            // the edit form writes to — not `logline`, which reels never set).
                            if !reel.reelDescription.isEmpty {
                                Text(reel.reelDescription)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 12)
                            }

                            // Featured Work — linked posts this reel references plus any
                            // hand-typed entries, listed in the same card style as a portfolio.
                            if !featuredWorks.isEmpty || !manualFeaturedWorks.isEmpty {
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Featured Work")
                                        .font(.title2)
                                        .fontWeight(.bold)

                                    VStack(spacing: 10) {
                                        ForEach(featuredWorks) { work in
                                            Button {
                                                selectedFeaturedWork = work
                                            } label: {
                                                SubmissionListRow(submission: work) { EmptyView() }
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        // Hand-typed entries: not tappable (no post to open).
                                        ForEach(manualFeaturedWorks) { entry in
                                            ManualFeaturedWorkRow(entry: entry)
                                        }
                                    }
                                }
                            }

                            // Moderator info
                            if UserDefaults.standard.bool(forKey: "isModeratorMode"), ModeratorAccess.isModerator {
                                Text("Submitted by \(reel.submittedBy)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                    .padding(.top, 16)
                            }
                            
                            // Edit and Delete buttons
                            if canEditOrDelete {
                                OwnerActionButtons(
                                    onEdit: { showEditSheet = true },
                                    onDelete: { showDeleteConfirmation = true }
                                )
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
        // Show the grabber so tall, scrollable detail pages can always be dismissed —
        // pulling the indicator drives the sheet directly, whereas a plain swipe over a
        // scrollable page gets eaten as scroll overscroll and snaps back.
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
                // Re-point at the (possibly replaced) local video and force a reload —
                // the new file often lives at the same path.
                resolvedVideoURL = updatedSubmission.videoURL
                videoReloadToken += 1
            }
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: reel)
        }
        .sheet(item: $selectedFeaturedWork) { work in
            featuredWorkDetail(for: work)
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
            orderedCrew: [
                OrderedEntry(role: "Director", name: "Ava Thompson"),
                OrderedEntry(role: "Scene Partner", name: "Liam O'Brien"),
                OrderedEntry(role: "Editor", name: "Priya Patel")
            ],
            reelType: "Dramatic",
            reelDescription: "Selected scenes from recent stage and screen work.",
            reelExperience: "5 years of theater and independent film.",
            reelSpecificSkills: "Stage combat, dialects, improv"
        ),
        liked: .constant(false)
    )
}
