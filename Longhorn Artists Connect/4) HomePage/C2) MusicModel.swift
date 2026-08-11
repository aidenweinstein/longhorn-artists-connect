//
//  MusicModel.swift
//  Longhorn Artists Connect
//
//  Backend logic for music submissions - handles audio playback, data management, and user interactions
//

import Foundation
import AVKit
import SwiftUI
import Combine

class MusicModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isAudioPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1
    @Published var isLoading = true
    @Published var contentLoaded = false
    
    // MARK: - Private Properties
    private var audioPlayer: AVPlayer?
    private var timeObserver: Any?
    
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
    
    // MARK: - Audio Player Management
    
    /// Setup audio player with the provided URL
    func setupAudioPlayer(url: URL) {
        audioPlayer = AVPlayer(url: url)
        
        // Monitor playback time
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = audioPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
        
        // Get duration
        Task {
            if let duration = try? await audioPlayer?.currentItem?.asset.load(.duration) {
                await MainActor.run {
                    self.duration = duration.seconds
                }
            }
        }
        
        // Listen for playback end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: audioPlayer?.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.isAudioPlaying = false
            self?.audioPlayer?.seek(to: .zero)
            self?.currentTime = 0
        }
    }
    
    /// Toggle play/pause state
    func togglePlayPause() {
        if isAudioPlaying {
            audioPlayer?.pause()
        } else {
            audioPlayer?.play()
        }
        isAudioPlaying.toggle()
    }
    
    /// Seek to a specific time in the audio
    func seek(to time: Double) {
        audioPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    /// Clean up audio player resources
    func cleanupAudioPlayer() {
        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
            timeObserver = nil // avoid removing the same token twice (a double-remove crashes)
        }
        audioPlayer?.pause()
        audioPlayer = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    deinit {
        cleanupAudioPlayer()
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
        await MainActor.run {
            isLoading = false
            contentLoaded = true
        }
    }
    
    // MARK: - Color Utilities
    
    /// Generate a consistent tint color based on title hash
    var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(submission.title.hashValue)
        return colors[hash % colors.count]
    }
}
