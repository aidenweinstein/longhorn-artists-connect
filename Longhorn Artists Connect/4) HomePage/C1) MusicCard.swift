//
//  MusicCard.swift
//  Longhorn Artists Connect
//
//  UI for Music submissions - Clean, customizable interface
//  Backend logic is in MusicModel.swift
//

import SwiftUI
import AVKit

struct MusicDetailView: View {
    let music: Submission
    @Binding var liked: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Backend model handles all logic
    @StateObject private var model: MusicModel

    @State private var selectedPortfolioName: CreditedPerson?

    // Icon color that adapts to light/dark mode
    private var iconColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    // UI State
    @State private var showSendMessage = false
    @State private var showDeleteConfirmation = false
    @State private var showReportSheet = false
    @State private var showEditSheet = false
    @State private var showCollectionPicker = false
    @State private var showFullScreenPoster = false
    
    init(music: Submission, liked: Binding<Bool>) {
        self.music = music
        self._liked = liked
        self._model = StateObject(wrappedValue: MusicModel(submission: music))
    }
    
    var body: some View {
        ZStack {
            // MARK: - Loading State
            if model.isLoading && !model.contentLoaded {
                VStack(spacing: 16) { // ⚙️ Spacing between spinner and text
                    ProgressView()
                        .scaleEffect(1.5) // ⚙️ Loading spinner size
                    Text("Loading...")
                        .font(.headline) // ⚙️ Loading text font
                        .foregroundStyle(.secondary) // ⚙️ Loading text color
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // MARK: - Main Content
                ScrollView {
                    VStack(spacing: 0) {
                        // Album Cover Section
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                showFullScreenPoster = true
                            } label: {
                                ZStack {
                                    if let thumbnailData = music.thumbnailData,
                                       let uiImage = UIImage(data: thumbnailData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(1.0, contentMode: .fit)
                                            .clipped()
                                    } else {
                                        Rectangle()
                                            .fill(LinearGradient(
                                                colors: [model.tintColor.opacity(0.55), model.tintColor.opacity(0.25)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(1.0, contentMode: .fit)
                                        Image(systemName: "music.note.circle.fill")
                                            .font(.system(size: 60, weight: .bold))
                                            .foregroundStyle(.white.opacity(0.9))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            
                            // Title, genres, explicit tag, and action buttons
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(music.title)
                                            .font(.system(size: 28, weight: .bold))
                                            .minimumScaleFactor(0.6)
                                            .lineLimit(2)
                                        
                                        // Artist name
                                        if !music.artist.isEmpty {
                                            Text(music.artist)
                                                .font(.title3)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        // Genres and explicit tag
                                        HStack(spacing: 8) {
                                            if !music.genres.isEmpty {
                                                Text(music.genres.joined(separator: " • "))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true) // Allow wrapping
                                            }
                                            
                                            if music.explicit {
                                                Text("Explicit")
                                                    .font(.subheadline)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(.red.opacity(0.2))
                                                    .foregroundStyle(.red)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Action buttons
                                    HStack(spacing: 6) { // Reduced from 12 to 6
                                        Button {
                                            model.toggleLike()
                                        } label: {
                                            Image(systemName: model.isLiked() ? "heart.fill" : "heart")
                                                .font(.system(size: 20))
                                                .foregroundStyle(model.isLiked() ? .red : .primary)
                                                .frame(width: 32, height: 32)
                                        }
                                        
                                        Button {
                                            showCollectionPicker = true
                                        } label: {
                                            Image(systemName: model.isInAnyCollection() ? "bookmark.fill" : "bookmark")
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
                            
                            // Audio Player Controls
                            if let audioURL = music.audioURL {
                                VStack(spacing: 8) {
                                    HStack(spacing: 12) {
                                        // Play/Pause button
                                        Button {
                                            model.togglePlayPause()
                                        } label: {
                                            Image(systemName: model.isAudioPlaying ? "pause.fill" : "play.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(.primary)
                                                .frame(width: 44, height: 44)
                                                .background(
                                                    Circle()
                                                        .fill(Color.secondary.opacity(0.1))
                                                )
                                        }
                                        
                                        // Progress bar and time labels
                                        VStack(spacing: 8) {
                                            GeometryReader { geometry in
                                                ZStack(alignment: .leading) {
                                                    Rectangle()
                                                        .fill(Color.secondary.opacity(0.3))
                                                        .frame(height: 4)
                                                    
                                                    Rectangle()
                                                        .fill(Color.brandOrange)
                                                        .frame(width: geometry.size.width * (model.duration > 0 ? CGFloat(model.currentTime / model.duration) : 0), height: 4)
                                                }
                                                .clipShape(Capsule())
                                                .gesture(
                                                    DragGesture(minimumDistance: 0)
                                                        .onChanged { value in
                                                            let newTime = Double(value.location.x / geometry.size.width) * model.duration
                                                            model.seek(to: max(0, min(newTime, model.duration)))
                                                        }
                                                        .onEnded { value in
                                                            let seekTime = Double(value.location.x / geometry.size.width) * model.duration
                                                            model.seek(to: seekTime)
                                                        }
                                                )
                                            }
                                            .frame(height: 4)
                                            
                                            HStack {
                                                Text(model.formatTime(model.currentTime))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .monospacedDigit()
                                                
                                                Spacer()
                                                
                                                Text(model.formatTime(model.duration))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .monospacedDigit()
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                                .onAppear {
                                    model.setupAudioPlayer(url: audioURL)
                                }
                                .onDisappear {
                                    model.cleanupAudioPlayer()
                                }
                            }
                        }
                        
                        // Music Information
                        VStack(alignment: .leading, spacing: 12) {
                            // Recording credits
                            if !music.orderedRecording.isEmpty {
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recording")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    ForEach(model.consolidatedCrew(music.orderedRecording), id: \.name) { consolidated in
                                        HStack(alignment: .top) {
                                            Text(consolidated.roles.joined(separator: ", "))
                                                .font(.body)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)

                                            Spacer()

                                            CreditNameView(name: consolidated.name, selection: $selectedPortfolioName)
                                        }
                                    }
                                }
                            }
                            
                            // Production credits
                            if !music.orderedProduction.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Production")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    ForEach(model.consolidatedCrew(music.orderedProduction), id: \.name) { consolidated in
                                        HStack(alignment: .top) {
                                            Text(consolidated.roles.joined(separator: ", "))
                                                .font(.body)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)

                                            Spacer()

                                            CreditNameView(name: consolidated.name, selection: $selectedPortfolioName)
                                        }
                                    }
                                }
                            }
                            
                            // Streaming links
                            if !music.spotifyLink.isEmpty || !music.appleMusicLink.isEmpty || !music.amazonMusicLink.isEmpty || !music.youtubeMusicLink.isEmpty || !music.soundcloudLink.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Listen On")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 16) {
                                        if !music.spotifyLink.isEmpty, let url = URL(string: music.spotifyLink) {
                                            Link(destination: url) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "music.note.list")
                                                        .font(.system(size: 32))
                                                        .foregroundStyle(.green)
                                                    Text("Spotify")
                                                        .font(.caption)
                                                        .foregroundStyle(.primary)
                                                }
                                                .frame(width: 60)
                                            }
                                        }
                                        
                                        if !music.appleMusicLink.isEmpty, let url = URL(string: music.appleMusicLink) {
                                            Link(destination: url) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "applelogo")
                                                        .font(.system(size: 32))
                                                        .foregroundStyle(.red)
                                                    Text("Apple")
                                                        .font(.caption)
                                                        .foregroundStyle(.primary)
                                                }
                                                .frame(width: 60)
                                            }
                                        }
                                        
                                        if !music.amazonMusicLink.isEmpty, let url = URL(string: music.amazonMusicLink) {
                                            Link(destination: url) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "music.note")
                                                        .font(.system(size: 32))
                                                        .foregroundStyle(.blue)
                                                    Text("Amazon")
                                                        .font(.caption)
                                                        .foregroundStyle(.primary)
                                                }
                                                .frame(width: 60)
                                            }
                                        }
                                        
                                        if !music.youtubeMusicLink.isEmpty, let url = URL(string: music.youtubeMusicLink) {
                                            Link(destination: url) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "play.circle")
                                                        .font(.system(size: 32))
                                                        .foregroundStyle(.red)
                                                    Text("YouTube")
                                                        .font(.caption)
                                                        .foregroundStyle(.primary)
                                                }
                                                .frame(width: 60)
                                            }
                                        }
                                        
                                        if !music.soundcloudLink.isEmpty, let url = URL(string: music.soundcloudLink) {
                                            Link(destination: url) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "cloud")
                                                        .font(.system(size: 32))
                                                        .foregroundStyle(.orange)
                                                    Text("SoundCloud")
                                                        .font(.caption)
                                                        .foregroundStyle(.primary)
                                                }
                                                .frame(width: 60)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Moderator info
                            if UserDefaults.standard.bool(forKey: "isModeratorMode") {
                                let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
                                let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
                                let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
                                
                                if currentUser == "Aiden Weinstein" {
                                    Text("Submitted by \(music.submittedBy)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal)
                                        .padding(.top, 16)
                                }
                            }
                            
                            // Edit and Delete buttons
                            if model.canEditOrDelete {
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
            Task {
                await model.simulateLoading()
            }
        }
        .sheet(item: $selectedPortfolioName) { person in
            PersonProfileView(name: person.name)
        }
        .sheet(isPresented: $showSendMessage) {
            SendPostMessageView(post: music)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentView(post: music)
        }
        .sheet(isPresented: $showEditSheet) {
            MusicEditView(submission: music) { updatedSubmission in
                model.update(updatedSubmission)
            }
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: music)
        }
        .fullScreenCover(isPresented: $showFullScreenPoster) {
            FullScreenPosterView(post: music, tintColor: model.tintColor)
        }
        .alert("Delete Music?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                model.delete()
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

}

#Preview {
    // Pretend a subset of the credited people already have Nexus accounts, so
    // those names render orange/clickable while the rest stay grey.
    let _ = UserDefaults.standard.set(
        ["Sofia Nguyen", "Marcus Bell"],
        forKey: "createdUserProfiles"
    )
    return MusicDetailView(
        music: Submission(
            id: UUID(),
            type: .music,
            title: "Sample Song",
            details: "A great track",
            genres: ["Indie", "Pop"],
            artist: "The Sample Band",
            orderedRecording: [
                OrderedEntry(role: "Vocals", name: "Sofia Nguyen"),
                OrderedEntry(role: "Guitar", name: "Liam O'Brien")
            ],
            orderedProduction: [
                OrderedEntry(role: "Producer", name: "Marcus Bell"),
                OrderedEntry(role: "Mixing", name: "Priya Patel")
            ]
        ),
        liked: .constant(false)
    )
}
