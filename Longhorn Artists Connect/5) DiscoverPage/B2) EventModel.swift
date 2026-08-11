//
//  EventModel.swift
//  Longhorn Artists Connect
//
//  Created by Aiden Weinstein on 2/12/26.
//
//  Backend logic for event submissions - handles data management, user interactions, and event-specific operations
//

import Foundation
import SwiftUI
import Combine

@MainActor
class EventModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isLoading = true
    @Published var contentLoaded = false
    @Published var showFullScreenFlyer = false
    
    // MARK: - Dependencies
    let event: Submission
    let store: SubmissionStore_3_2
    
    // MARK: - Initialization
    init(event: Submission, store: SubmissionStore_3_2 = .shared) {
        self.event = event
        self.store = store
    }
    
    // MARK: - Permissions
    
    /// Check if the current user can edit or delete this event
    var canEditOrDelete: Bool {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == event.submittedBy
        
        let isModeratorMode = UserDefaults.standard.bool(forKey: "isModeratorMode")
        let isAidenWeinstein = currentUser == "Aiden Weinstein"
        let canUseModerator = isModeratorMode && isAidenWeinstein
        
        return isUserCreator || canUseModerator
    }
    
    /// Check if moderator info should be shown
    var shouldShowModeratorInfo: Bool {
        guard UserDefaults.standard.bool(forKey: "isModeratorMode") else { return false }
        
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        
        return currentUser == "Aiden Weinstein"
    }
    
    // MARK: - Event Information
    
    /// Check if event has a valid flyer image
    var hasFlyer: Bool {
        event.thumbnailData != nil
    }
    
    /// Check if event has tickets URL
    var hasTicketsURL: Bool {
        guard let ticketsURL = event.eventTicketsURL else { return false }
        return !ticketsURL.isEmpty
    }
    
    /// Get formatted event date string (without year)
    var formattedEventDate: String {
        guard let startDate = event.eventStartDate else { return "" }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d" // e.g., "Feb 15"
        
        return formatter.string(from: startDate)
    }
    
    /// Get formatted event time range
    var formattedEventTime: String {
        guard let startDate = event.eventStartDate else { return "" }
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a" // e.g., "7:00 PM"
        
        if let endDate = event.eventEndDate,
           Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            // Same day event - show time range
            return "\(timeFormatter.string(from: startDate)) - \(timeFormatter.string(from: endDate))"
        } else {
            // Just show start time
            return timeFormatter.string(from: startDate)
        }
    }
    
    /// Get full formatted date and time
    var formattedDateTime: String {
        let date = formattedEventDate
        let time = formattedEventTime
        
        if !date.isEmpty && !time.isEmpty {
            return "\(date) • \(time)"
        } else if !date.isEmpty {
            return date
        } else if !time.isEmpty {
            return time
        } else {
            return ""
        }
    }
    
    /// Extract venue name from full location (before first comma)
    var venueName: String {
        guard let location = event.eventLocation, !location.isEmpty else { return "" }
        
        if let commaIndex = location.firstIndex(of: ",") {
            return String(location[..<commaIndex])
        }
        return location
    }
    
    // MARK: - Location Handling
    
    /// Open event location in Apple Maps
    func openLocationInMaps() {
        guard let location = event.eventLocation, !location.isEmpty else { return }
        
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
    
    /// Get Apple Maps URL for the event location
    func getAppleMapsURL() -> URL? {
        guard let location = event.eventLocation, !location.isEmpty else { return nil }
        guard let encodedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "maps://?q=\(encodedLocation)")
    }
    
    // MARK: - Tickets Handling
    
    /// Open tickets URL in browser
    func openTicketsURL() {
        guard let ticketsURLString = event.eventTicketsURL,
              !ticketsURLString.isEmpty,
              let url = URL(string: ticketsURLString) else {
            return
        }
        
        UIApplication.shared.open(url)
    }
    
    /// Get tickets URL
    func getTicketsURL() -> URL? {
        guard let ticketsURLString = event.eventTicketsURL,
              !ticketsURLString.isEmpty else {
            return nil
        }
        return URL(string: ticketsURLString)
    }
    
    // MARK: - User Interactions
    
    /// Toggle like status for this event
    func toggleLike() {
        store.toggleLike(for: event)
    }
    
    /// Check if this event is liked
    func isLiked() -> Bool {
        store.isLiked(event)
    }
    
    /// Check if this event is in any collection
    func isInAnyCollection() -> Bool {
        store.isInAnyCollection(event)
    }
    
    /// Delete this event
    func delete() {
        store.delete(event)
    }
    
    /// Update this event
    func update(_ updated: Submission) {
        store.update(updated)
    }
    
    // MARK: - Calendar Integration
    
    /// Add event to iOS Calendar (future feature)
    func addToCalendar() {
        // TODO: Implement EventKit integration to add event to iOS Calendar
        print("📅 Add to calendar: \(event.title)")
    }
    
    // MARK: - Sharing
    
    /// Get shareable event info
    func getShareableInfo() -> String {
        var info = event.title
        
        if !event.eventHost.isEmpty {
            info += "\nHost: \(event.eventHost)"
        }
        
        if let location = event.eventLocation, !location.isEmpty {
            info += "\nLocation: \(location)"
        }
        
        if !formattedDateTime.isEmpty {
            info += "\nWhen: \(formattedDateTime)"
        }
        
        if let ticketsURL = event.eventTicketsURL, !ticketsURL.isEmpty {
            info += "\nTickets: \(ticketsURL)"
        }
        
        return info
    }
    
    /// Share event via iOS share sheet
    func shareEvent() {
        let shareText = getShareableInfo()
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Loading State
    
    /// Simulate loading with delay
    func simulateLoading(delay: TimeInterval = 0.3) async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        isLoading = false
        contentLoaded = true
    }
    
    // MARK: - Color Utilities
    
    /// Generate a consistent tint color based on title hash
    var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(event.title.hashValue)
        return colors[hash % colors.count]
    }
    
    // MARK: - Date/Time Utilities
    
    /// Check if event is in the past
    var isPastEvent: Bool {
        guard let startDate = event.eventStartDate else { return false }
        return startDate < Date()
    }
    
    /// Check if event is happening today
    var isToday: Bool {
        guard let startDate = event.eventStartDate else { return false }
        return Calendar.current.isDateInToday(startDate)
    }
    
    /// Check if event is happening this week
    var isThisWeek: Bool {
        guard let startDate = event.eventStartDate else { return false }
        return Calendar.current.isDate(startDate, equalTo: Date(), toGranularity: .weekOfYear)
    }
    
    /// Get countdown to event
    var countdownToEvent: String {
        guard let startDate = event.eventStartDate else { return "" }
        
        let now = Date()
        if startDate < now {
            return "Event has passed"
        }
        
        let components = Calendar.current.dateComponents([.day, .hour], from: now, to: startDate)
        
        if let days = components.day, days > 0 {
            return "\(days) day\(days == 1 ? "" : "s") away"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") away"
        } else {
            return "Starting soon"
        }
    }
}
