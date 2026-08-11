//
//  FilmModel.swift
//  Longhorn Artists Connect
//
//  Backend logic for film submissions - handles video playback, data management, and user interactions
//

import Foundation
import AVKit
import SwiftUI
import Combine

@MainActor
class FilmModel: ObservableObject {
    // MARK: - Published Properties
    @Published var player: AVPlayer?
    @Published var showControls = false
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1
    @Published var showFullScreen = false
    @Published var isLoading = true
    @Published var contentLoaded = false
    
    // MARK: - Private Properties
    private var controlsWorkItem: DispatchWorkItem?
    
    // MARK: - Dependencies
    let submission: Submission
    let store: SubmissionStore_3_2
    
    // MARK: - Initialization
    init(submission: Submission, store: SubmissionStore_3_2 = .shared) {
        self.submission = submission
        self.store = store
    }
    
    // MARK: - Permissions
    
    /// Check if the current user can edit or delete this submission
    var canEditOrDelete: Bool {
        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let userLastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let currentUser = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        let isUserCreator = !currentUser.isEmpty && currentUser == submission.submittedBy
        
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
    
    // MARK: - Video Player Management
    
    /// Setup video player with the provided URL
    func setupPlayer(url: URL) {
        guard player == nil else { return }
        player = AVPlayer(url: url)
        
        // Monitor playback time
        player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
        
        // Get duration and restore saved position
        Task {
            if let duration = try? await player?.currentItem?.asset.load(.duration) {
                await MainActor.run {
                    self.duration = duration.seconds
                    
                    // Restore saved playback position if available
                    if let savedPosition = store.getPlaybackPosition(for: submission.id),
                       savedPosition > 0 && savedPosition < self.duration - 1 {
                        player?.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 600))
                        currentTime = savedPosition
                    }
                }
            }
        }
    }
    
    /// Start playing the video
    func playVideo() {
        player?.play()
        isPlaying = true
    }
    
    /// Toggle play/pause state
    func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    /// Seek to a specific time in the video
    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    /// Toggle controls visibility
    func toggleControls() {
        showControls.toggle()
        
        // Cancel previous auto-hide
        controlsWorkItem?.cancel()
        
        // Schedule auto-hide if controls are shown
        if showControls {
            scheduleControlsAutoHide()
        }
    }
    
    /// Schedule controls to auto-hide after 3 seconds
    func scheduleControlsAutoHide() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.showControls = false
        }
        controlsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }
    
    /// Save playback position before cleanup
    func savePlaybackPosition() {
        if currentTime > 0 && currentTime < duration - 1 {
            store.savePlaybackPosition(for: submission.id, position: currentTime)
        }
    }
    
    /// Clean up video player resources
    func cleanupPlayer() {
        player?.pause()
        controlsWorkItem?.cancel()
    }
    
    // MARK: - Data Formatting
    
    /// Format time in MM:SS format
    func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Consolidate crew members who have multiple roles
    func consolidatedCrew(_ crew: [OrderedEntry]) -> [(name: String, roles: [String])] {
        var grouped: [String: [String]] = [:]
        var order: [String] = []
        
        for entry in crew {
            if grouped[entry.name] == nil {
                order.append(entry.name)
                grouped[entry.name] = []
            }
            grouped[entry.name]?.append(entry.role)
        }
        
        return order.map { name in
            (name: name, roles: grouped[name] ?? [])
        }
    }
    
    /// Get video duration from URL
    static func getVideoDuration(from url: URL) async -> Double {
        let asset = AVAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds
        } catch {
            print("Error getting video duration: \(error.localizedDescription)")
            return 0
        }
    }
    
    // MARK: - User Interactions
    
    /// Toggle like status for this submission
    func toggleLike() {
        store.toggleLike(for: submission)
    }
    
    /// Check if this submission is liked
    func isLiked() -> Bool {
        store.isLiked(submission)
    }
    
    /// Check if this submission is in any collection
    func isInAnyCollection() -> Bool {
        store.isInAnyCollection(submission)
    }
    
    /// Delete this submission
    func delete() {
        store.delete(submission)
    }
    
    /// Update this submission
    func update(_ updated: Submission) {
        store.update(updated)
    }
    
    /// Show portfolio or invite for a user
    func showPortfolioOrInvite(for name: String) {
        // TODO: Check if user exists in the system
        // For now, show an alert with invite option
        let alert = UIAlertController(
            title: "Invite \(name) to Nexus",
            message: "Would you like to invite \(name) to join Nexus?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Invite", style: .default) { _ in
            // TODO: Send invitation
            print("Inviting \(name) to Nexus")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
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
        let hash = abs(submission.title.hashValue)
        return colors[hash % colors.count]
    }
}
