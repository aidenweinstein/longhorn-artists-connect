//
//  HomePostCard.swift
//  Longhorn Artists Connect
//
//  Card view for posts in the home feed
//

import SwiftUI
import AVKit

struct HomePostCard: View {
    let post: Submission
    let showTypeIcon: Bool
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @State private var showOptions = false
    @State private var showProjectDetail = false
    @State private var showSendMessage = false
    @State private var showReportSheet = false
    @State private var showCollectionPicker = false
    @State private var videoDuration: Double?
    @State private var thumbnailImage: UIImage? // Cache the image
    @Environment(\.colorScheme) private var colorScheme
    
    // Generate a consistent color for each post based on title
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(post.title.hashValue)
        return colors[hash % colors.count]
    }
    
    // Icon color that adapts to light/dark mode
    private var iconColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    // Get the icon for the post type
    private var typeIcon: String {
        switch post.type {
        case .film:
            return "film"
        case .music:
            return "music.note"
        case .reel:
            return "star.fill"
        case .project:
            return "doc.text"
        case .event:
            return "calendar"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Media thumbnail - adapts to content aspect ratio
            Button {
                showProjectDetail = true
            } label: {
                ZStack(alignment: .bottomLeading) {
                    // Thumbnail image (scaled to fill) - use cached image
                    if let thumbnailImage {
                        Image(uiImage: thumbnailImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .clipped()
                    } else {
                        // Background color/gradient fallback
                        Rectangle()
                            .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .aspectRatio(16.0/9.0, contentMode: .fit)
                    }
                    
                    // Video duration overlay for film posts
                    if post.type == .film, let duration = videoDuration {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(formatDuration(duration))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(.black.opacity(0.7))
                                    )
                                    .padding(8)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .task {
                // Load thumbnail image once on appear
                if thumbnailImage == nil, let thumbnailData = post.thumbnailData {
                    thumbnailImage = UIImage(data: thumbnailData)
                }
                
                // Load video duration if it's a film (async and cached)
                if post.type == .film, videoDuration == nil, let videoURL = post.videoURL {
                    videoDuration = await getVideoDuration(from: videoURL)
                }
            }

            // Title and actions below the media
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Button {
                        showProjectDetail = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if showTypeIcon {
                                    Image(systemName: typeIcon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Text(post.title)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            
                            // Show credit based on post type
                            if post.type == .film {
                                // For film, find director from crew
                                if let director = post.orderedCrew.first(where: { $0.role.lowercased().contains("director") }) {
                                    Text("Directed by \(director.name)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else if !post.submittedBy.isEmpty {
                                    // Fallback to submitter if no director found
                                    Text("Directed by \(post.submittedBy)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } else if post.type == .music {
                                // For music, show artist if available
                                if !post.artist.isEmpty {
                                    Text("By \(post.artist)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } else if post.type == .reel {
                                // For reel, find editor from crew or use submitter
                                if let editor = post.orderedCrew.first(where: { $0.role.lowercased().contains("editor") || $0.role.lowercased().contains("edit") }) {
                                    Text("Edited by \(editor.name)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else if !post.submittedBy.isEmpty {
                                    // Fallback to submitter if no editor found
                                    Text("Edited by \(post.submittedBy)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: 8) { // Reduced from 16 to 8
                        Button { 
                            store.toggleLike(for: post)
                        } label: {
                            Image(systemName: store.isLiked(post) ? "heart.fill" : "heart")
                                .foregroundStyle(store.isLiked(post) ? .red : .primary)
                                .font(.system(size: 22))
                        }
                        Button { 
                            showCollectionPicker = true
                        } label: {
                            Image(systemName: store.isInAnyCollection(post) ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 22))
                                .foregroundStyle(iconColor)
                        }
                        Button { 
                            showSendMessage = true
                        } label: {
                            Image(systemName: "paperplane")
                                .font(.system(size: 22))
                                .foregroundStyle(iconColor)
                        }
                        Button { 
                            showReportSheet = true
                        } label: {
                            Image(systemName: "flag")
                                .font(.system(size: 22))
                                .foregroundStyle(iconColor)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
                
                // Divider only in the padded area
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showProjectDetail) {
            ProjectDetailView(post: post, liked: .constant(store.isLiked(post)))
        }
        .sheet(isPresented: $showSendMessage) {
            SendPostMessageView(post: post)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentView(post: post)
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(post: post)
        }
    }
    
    // Helper function to get video duration
    private func getVideoDuration(from url: URL) async -> Double {
        let asset = AVAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds
        } catch {
            print("Error getting video duration: \(error.localizedDescription)")
            return 0
        }
    }
    
    // Helper function to format duration as MM:SS
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
