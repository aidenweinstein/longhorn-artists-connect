//
//  PostDetailRouter.swift
//  Longhorn Artists Connect
//
//  Created by Aiden Weinstein on 2/15/26.
//
//  This file contains the router that directs Home feed posts to their appropriate detail views.
//  Each media type (Film, Music, Reel) has a specialized detail view.
//  Projects and Events are never shown in Home feed - they only appear in Discover.

import SwiftUI

// MARK: - Post Detail Router

/// Routes to the appropriate specialized detail view based on submission type
/// Note: This is only used for Home feed posts (Film, Music, Reel)
/// Projects and Events have their own detail views in Discover (UpcomingProjectDetailView, EventDetailView)
struct PostDetailRouter: View {
    let post: Submission
    @Binding var liked: Bool
    
    var body: some View {
        Group {
            switch post.type {
            case .film:
                FilmDetailView(film: post, liked: $liked)
            case .music:
                MusicDetailView(music: post, liked: $liked)
            case .reel:
                ReelDetailView(reel: post, liked: $liked)
            case .project, .event:
                // These should never appear in Home feed - they're filtered out
                // Projects use: UpcomingProjectDetailView (in ProjectCard.swift)
                // Events use: EventDetailView (in EventCard.swift)
                EmptyView()
            }
        }
    }
}

// MARK: - Backward Compatibility Alias

/// Legacy name for compatibility with existing code
/// Use PostDetailRouter instead
typealias ProjectDetailView = PostDetailRouter
