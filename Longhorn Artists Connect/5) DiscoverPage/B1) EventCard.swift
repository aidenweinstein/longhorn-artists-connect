//
//  EventCard.swift
//  Longhorn Artists Connect
//
//  Created by Aiden Weinstein on 2/12/26.
//
//  This file contains UI components for displaying events in the Discover feed
//  and the detail view for events with dates, locations, and ticket links.

import SwiftUI

// MARK: - Event Card Component (for Discover Feed)

struct EventCard: View {
    let event: Submission
    
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(event.title.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Flyer/poster on left
                ZStack {
                    if let thumbnailData = event.thumbnailData,
                       let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 180)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(
                                VStack(spacing: 4) {
                                    if let startDate = event.eventStartDate {
                                        Text(startDate, format: .dateTime.month(.abbreviated))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.white.opacity(0.9))
                                        
                                        Text(startDate, format: .dateTime.day())
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundStyle(.white)
                                    } else {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                            )
                    }
                }
                .frame(width: 120, height: 180)
                .clipped() // Remove rounded corners, just clip to frame
                
                // Event info on right
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Logline - shows as much as possible without pushing content below poster
                    if !event.logline.isEmpty {
                        Text(event.logline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Event date and time - centered between logline and button
                    if let startDate = event.eventStartDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 4) {
                                Text(startDate, format: .dateTime.month().day())
                                    .font(.subheadline)
                                
                                if let endDate = event.eventEndDate,
                                   Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                                    Text("•")
                                        .font(.subheadline)
                                    Text("\(startDate, format: .dateTime.hour().minute()) - \(endDate, format: .dateTime.hour().minute())")
                                        .font(.subheadline)
                                } else {
                                    Text("•")
                                        .font(.subheadline)
                                    Text(startDate, format: .dateTime.hour().minute())
                                        .font(.subheadline)
                                }
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    // Location - centered between logline and button
                    if let location = event.eventLocation, !location.isEmpty {
                        Button {
                            openLocationInMaps(location: location)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.caption)
                                Text(extractVenueName(from: location))
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.brandOrange)
                        }
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Tickets button at bottom
                    if let ticketsURL = event.eventTicketsURL,
                       !ticketsURL.isEmpty,
                       let url = URL(string: ticketsURL) {
                        Link(destination: url) {
                            Text("Tickets")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.brandOrange)
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 180, alignment: .top)
            }
            .padding(.vertical, 16)
        }
    }
    
    private func openLocationInMaps(location: String) {
        guard let encodedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "maps://?q=\(encodedLocation)") else {
            return
        }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            if let webURL = URL(string: "https://maps.apple.com/?q=\(encodedLocation)") {
                UIApplication.shared.open(webURL)
            }
        }
    }
    
    private func extractVenueName(from location: String) -> String {
        if let commaIndex = location.firstIndex(of: ",") {
            return String(location[..<commaIndex])
        }
        return location
    }
}

// MARK: - Event Detail View

struct EventDetailView: View {
    let event: Submission
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    
    @State private var isLoading = true
    @State private var contentLoaded = false
    @State private var showFullScreenPoster = false
    
    // Check if current user is the event creator or a moderator
    private var canEditOrDelete: Bool {
        // Check if user is the creator
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == event.submittedBy
        
        // Debug logging
        print("🔍 [Event] Edit/Delete Permission Check:")
        print("   Current User: '\(currentUser)'")
        print("   Event Submitted By: '\(event.submittedBy)'")
        print("   Is User Creator: \(isUserCreator)")
        
        // Check if user is a moderator (only Aiden Weinstein)
        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let isAidenWeinstein = currentUser == "Aiden Weinstein"
        let canUseModerator = isModeratorMode && isAidenWeinstein
        
        print("   Is Moderator Mode: \(isModeratorMode)")
        print("   Is Aiden Weinstein: \(isAidenWeinstein)")
        print("   Can Edit/Delete: \(isUserCreator || canUseModerator)")
        
        return isUserCreator || canUseModerator
    }
    
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(event.title.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            if isLoading && !contentLoaded {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Main content
                ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Space for drag indicator
                    Color.clear.frame(height: 30)
                    
                    // Poster and info side-by-side (like projects)
                    HStack(alignment: .center, spacing: 16) {
                        // Poster on left - clickable for fullscreen
                        Button {
                            showFullScreenPoster = true
                        } label: {
                            if let thumbnailData = event.thumbnailData,
                               let uiImage = UIImage(data: thumbnailData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 235)
                                    .clipped() // No rounded corners
                            } else {
                                ZStack {
                                    Rectangle()
                                        .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))

                                    Image(systemName: "calendar")
                                        .font(.system(size: 72))
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .frame(width: 235, height: 353)
                                .clipped() // No rounded corners
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 20) // Nudge the flyer down
                        
                        // Info on right
                        VStack(alignment: .center, spacing: 8) {
                            // Title - centered
                            Text(event.title)
                                .font(.system(size: 24, weight: .bold))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                            
                            // About text (logline) - centered, like project logline
                            if !event.logline.isEmpty {
                                Text(event.logline)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal)
                    
                    // Details Section
                    if !event.eventHost.isEmpty || event.eventLocation != nil || event.eventStartDate != nil {
                        Divider()
                            .padding(.top, 12)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Details")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                // Host
                                if !event.eventHost.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.fill")
                                            .font(.caption)
                                        Text(event.eventHost)
                                            .font(.subheadline)
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                }

                                // Location - clickable
                                if let location = event.eventLocation, !location.isEmpty {
                                    Button {
                                        openLocationInMaps(location: location)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "location.fill")
                                                .font(.caption)
                                            Text(location)
                                                .font(.subheadline)
                                                .multilineTextAlignment(.leading)
                                        }
                                        .foregroundStyle(Color.brandOrange)
                                        .padding(.horizontal)
                                    }
                                }

                                // Date and time
                                if let startDate = event.eventStartDate {
                                    HStack(spacing: 4) {
                                        Image(systemName: "calendar")
                                            .font(.caption)

                                        HStack(spacing: 4) {
                                            // Date without year
                                            Text(startDate, format: .dateTime.month().day())
                                                .font(.subheadline)

                                            // Time range (start-end)
                                            if let endDate = event.eventEndDate,
                                               Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                                                Text("•")
                                                    .font(.subheadline)
                                                Text("\(startDate, format: .dateTime.hour().minute()) - \(endDate, format: .dateTime.hour().minute())")
                                                    .font(.subheadline)
                                            } else {
                                                Text("•")
                                                    .font(.subheadline)
                                                Text(startDate, format: .dateTime.hour().minute())
                                                    .font(.subheadline)
                                            }
                                        }
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // Buy Ticket button (if tickets URL is provided)
                        if let ticketsURL = event.eventTicketsURL,
                           !ticketsURL.isEmpty,
                           let url = URL(string: ticketsURL) {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "ticket")
                                    Text("Buy Ticket")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.brandOrange)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        
                        // Edit and Delete buttons for creator or moderator
                        if canEditOrDelete {
                            HStack(spacing: 12) {
                                // Edit button
                                Button {
                                    // TODO: Add edit functionality
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
                                
                                // Delete button
                                Button {
                                    store.delete(event)
                                    dismiss()
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
                        }
                    }
                    .padding()
                }
                }
            .ignoresSafeArea(edges: .all)
            }
            
            // Drag indicator at the top (show even during loading)
            VStack {
                Capsule()
                    .fill(Color.white)
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                
                Spacer()
            }
        }
        .presentationDragIndicator(.hidden)
        .fullScreenCover(isPresented: $showFullScreenPoster) {
            EventFullScreenPosterView(event: event, tintColor: tintColor)
        }
        .onAppear {
            // Simulate loading delay using Swift Concurrency
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation {
                    isLoading = false
                    contentLoaded = true
                }
            }
        }
    }
    
    private func openLocationInMaps(location: String) {
        // Encode the location for URL
        guard let encodedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "maps://?q=\(encodedLocation)") else {
            return
        }
        
        // Try to open in Apple Maps
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // Fallback to web version
            if let webURL = URL(string: "https://maps.apple.com/?q=\(encodedLocation)") {
                UIApplication.shared.open(webURL)
            }
        }
    }
}

// MARK: - Event Full Screen Poster View

struct EventFullScreenPosterView: View {
    let event: Submission
    let tintColor: Color
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Poster image
            if let thumbnailData = event.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Close button in top right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.black.opacity(0.5))
                            )
                            .contentShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

#Preview("Event Card") {
    EventCard(event: .placeholderEventV2)
        .padding(.horizontal)
}

#Preview("Event Detail") {
    EventDetailView(event: .placeholderEventV2)
}
