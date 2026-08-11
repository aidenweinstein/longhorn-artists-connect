import SwiftUI
import PhotosUI
import CloudKit

struct Portfolio_5: View {
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    
    // Onboarding data
    @AppStorage("userFirstName") private var userFirstName: String = ""
    @AppStorage("userLastName") private var userLastName: String = ""
    @AppStorage("userGraduationYear") private var userGraduationYear: String = ""
    @AppStorage("userType") private var userType: String = ""
    @AppStorage("userBio") private var userBio: String = ""
    @AppStorage("userMajor") private var userMajor: String = ""
    @AppStorage("userMinor") private var userMinor: String = ""
    @AppStorage("userCertificate") private var userCertificate: String = ""
    @AppStorage("userHometown") private var userHometown: String = ""
    @AppStorage("profileImageOffsetX") private var profileImageOffsetX: Double = 0
    @AppStorage("profileImageOffsetY") private var profileImageOffsetY: Double = 0
    @AppStorage("profileImageScale") private var profileImageScale: Double = 1.0
    @AppStorage("appearanceMode") private var appearanceMode: String = "automatic" // "light", "dark", or "automatic"
    
    // Legacy storage (kept for backward compatibility)
    @AppStorage("profileName") private var profileName: String = ""
    @AppStorage("graduationYear") private var graduationYear: Int = 0
    @AppStorage("profileImageData") private var profileImageData: Data = Data()
    
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("isModeratorMode") private var isModeratorMode: Bool = false
    @AppStorage("isGuestUser") private var isGuestUser: Bool = false
    
    @State private var showingLogin = false
    @State private var showingSettings = false
    @State private var tempFirstName = ""
    @State private var tempLastName = ""
    @State private var tempYear = ""
    @State private var tempUserTypes: Set<String> = []
    @State private var tempBio = ""
    @State private var tempMajor = ""
    @State private var tempMinor = ""
    @State private var tempCertificate = ""
    @State private var tempHometown = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var tempImageData: Data? = nil
    @State private var tempImageOffsetX: Double = 0
    @State private var tempImageOffsetY: Double = 0
    @State private var tempImageScale: Double = 1.0
    @State private var showImageAdjustment = false
    @State private var imageWasRemoved = false // Track if user explicitly removed the image
    @State private var selectedProject: Submission?
    @State private var liked = false
    
    // Define colors as static constants to prevent color changes on tab switch
    private static let darkBrownColor = Color(red: 80/255, green: 50/255, blue: 30/255).opacity(1.0)  // Darker for unselected
    private static let mediumBrownColor = Color(red: 140/255, green: 90/255, blue: 55/255).opacity(1.0)  // Brighter for selected
    
    // Computed property for full name
    private var displayName: String {
        if !userFirstName.isEmpty || !userLastName.isEmpty {
            return "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
        } else if !profileName.isEmpty {
            return profileName
        } else {
            return "Your Name"
        }
    }
    
    // Get user's approved submissions (excluding events and projects)
    private var userSubmissions: [Submission] {
        store.approvedSubmissions.filter { submission in
            submission.submittedBy == displayName && 
            submission.type != .event && 
            submission.type != .project
        }
    }
    
    // Computed property for graduation year
    private var displayGraduationYear: String {
        if !userGraduationYear.isEmpty {
            return userGraduationYear
        } else if graduationYear > 0 {
            return String(graduationYear)
        } else {
            return ""
        }
    }
    
    // Load profile image
    private var profileImage: UIImage? {
        // First check if we have image data
        if let uiImage = UIImage(data: profileImageData), !profileImageData.isEmpty {
            return uiImage
        }
        
        // Then check if there's a saved image from onboarding
        if let imagePath = UserDefaults.standard.string(forKey: "profileImagePath"),
           let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)),
           let image = UIImage(data: imageData) {
            return image
        }
        
        return nil
    }
    
    // Get user's roles in a specific submission
    private func getUserRolesInSubmission(_ submission: Submission) -> String? {
        // Check cast - always return "Actor" for cast members
        for castEntry in submission.orderedCast {
            if castEntry.name == displayName {
                return "Actor"
            }
        }
        
        // Check crew - return actual crew roles
        var roles: [String] = []
        for crewEntry in submission.orderedCrew {
            if crewEntry.name == displayName {
                roles.append(crewEntry.role)
            }
        }
        
        if !roles.isEmpty {
            return roles.joined(separator: ", ")
        }
        
        // If no roles found, return the submission type
        return submission.type.rawValue
    }
    
    // Refresh portfolio data
    private func refreshPortfolio() async {
        // Refresh submissions from CloudKit
        await store.syncWithCloudKit()
        
        // Small delay for better UX
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: feedFormat.sectionSpacing) {
                        profileHeaderView
                        bioView
                        Divider()
                        submissionsView
                    }
                    // ====== UI CONTROLS!!!!! ======
                    .padding(feedFormat.contentPadding)
                    // ==============================
                }
                .refreshable {
                    await refreshPortfolio()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingLogin) {
                editProfileSheet
            }
            .sheet(item: $selectedProject) { project in
                ProjectDetailView(post: project, liked: $liked)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    appearanceMode: $appearanceMode,
                    isModeratorMode: $isModeratorMode
                )
            }
            .onAppear {
                applyAppearanceMode()
            }
        }
    }
    
    // MARK: - View Components
    
    private var profileHeaderView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                profileImageView
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.largeTitle)
                        .bold()
                    academicInfoView
                }
                Spacer(minLength: 0)
            }

            if !userType.isEmpty {
                userTypeBubbles
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileImageView: some View {
        Group {
            if let profileImage {
                GeometryReader { geometry in
                    Image(uiImage: profileImage)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(profileImageScale)
                        // Offsets are saved in the adjuster's 300pt preview space,
                        // so scale them to this (smaller) frame to match exactly.
                        .offset(x: CGFloat(profileImageOffsetX) * feedFormat.profileImageSize / ImageAdjustmentView.previewSize,
                                y: CGFloat(profileImageOffsetY) * feedFormat.profileImageSize / ImageAdjustmentView.previewSize)
                        // ====== UI CONTROLS!!!!! ======
                        .frame(width: feedFormat.profileImageSize, height: feedFormat.profileImageSize)
                        // ==============================
                        .clipShape(Circle())
                }
                // ====== UI CONTROLS!!!!! ======
                .frame(width: feedFormat.profileImageSize, height: feedFormat.profileImageSize)
                // ==============================
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    // ====== UI CONTROLS!!!!! ======
                    .frame(width: feedFormat.profileImageSize, height: feedFormat.profileImageSize)
                    // ==============================
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var academicInfoView: some View {
        // Abbreviate the graduation year to save room, e.g. "2026" → "'26".
        let shortYear = displayGraduationYear.isEmpty ? "" : "'\(displayGraduationYear.suffix(2))"
        let parts = [
            shortYear.isEmpty ? "" : "Class of \(shortYear)",
            userMajor
        ].filter { !$0.isEmpty }
        // Keep class + major on a single line, shrinking the text before it wraps.
        return Text(parts.joined(separator: " • "))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
    
    private var userTypeBubbles: some View {
        FlowLayout(spacing: 6) {
            ForEach(userType.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, id: \.self) { role in
                Text(role)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    // ====== UI CONTROLS!!!!! ======
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.utBrandOrange)
                    .cornerRadius(8)
                    // ==============================
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var bioView: some View {
        Text(userBio.isEmpty ? "Personal description goes here. This is where you introduce yourself and your work." : userBio)
            .foregroundStyle(userBio.isEmpty ? .secondary : .primary)
            .italic(userBio.isEmpty)
    }
    
    private var submissionsView: some View {
        Group {
            if userSubmissions.isEmpty {
                Text(isGuestUser ? "Guest account. Enjoy exploring the Nexus!" : "No projects yet. Create something amazing!")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: feedFormat.rowSpacing) {
                    ForEach(userSubmissions) { submission in
                        submissionButton(for: submission)
                    }
                }
            }
        }
    }
    
    private func submissionButton(for submission: Submission) -> some View {
        Button {
            selectedProject = submission
        } label: {
            HStack(spacing: 12) {
                submissionThumbnail(for: submission)
                submissionInfo(for: submission)
                Spacer()
            }
            .padding(8)
            // ====== UI CONTROLS!!!!! ======
            // Fixed dark mode glitch - using proper adaptive background
            .background(Color(UIColor.secondarySystemGroupedBackground))
            // ==============================
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func submissionThumbnail(for submission: Submission) -> some View {
        if let thumbnailData = submission.thumbnailData,
           let uiImage = UIImage(data: thumbnailData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                // ====== UI CONTROLS!!!!! ======
                .frame(width: feedFormat.thumbnailWidth)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                // ==============================
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                // ====== UI CONTROLS!!!!! ======
                .frame(width: feedFormat.thumbnailWidth, height: feedFormat.thumbnailWidth * 0.6)
                .cornerRadius(8)
                // ==============================
                .overlay(
                    Image(systemName: submission.type == .film ? "film" : "music.note")
                        .foregroundStyle(.secondary)
                )
        }
    }
    
    private func submissionInfo(for submission: Submission) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(submission.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            if let userRoles = getUserRolesInSubmission(submission) {
                Text(userRoles)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            // Like count button
            LikeCountButton(submissionId: submission.id)
        }
    }
    
    // MARK: - Toolbar Format Per Screen Size
    /// Tunable toolbar item sizes and positions for the Portfolio page.
    /// - `editWidth/editFontSize`: size of the Edit pill.
    /// - `settingsWidth/settingsFontSize`: size of the settings (hamburger) pill.
    /// - `pillHeight`: shared height of both pills.
    /// - `pillOffsetX/Y`: nudges both pills from their default spot.
    /// - `logoHeight`: height of the Portfolio logo image.
    private struct ToolbarFormat {
        var editWidth: CGFloat
        var editFontSize: CGFloat
        var settingsWidth: CGFloat
        var settingsFontSize: CGFloat
        var pillHeight: CGFloat
        var pillOffsetX: CGFloat
        var pillOffsetY: CGFloat
        var logoHeight: CGFloat
        // iPad-only knobs (default to no-ops so iPhone layout is unaffected):
        /// Extra horizontal/vertical nudge applied to the logo.
        var logoOffsetX: CGFloat = 0
        var logoOffsetY: CGFloat = 0
        /// Fixed length (width) of the Edit pill. `nil` falls back to `editWidth`.
        var pillLength: CGFloat? = nil
        /// How far down the orange toolbar bar extends.
        var barHeight: CGFloat = 60
    }

    /// Adjust the values in each case to tune the toolbar for that screen size.
    private var toolbarFormat: ToolbarFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return ToolbarFormat(editWidth: 45, editFontSize: 14, settingsWidth: 43, settingsFontSize: 18, pillHeight: 40, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 43)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(editWidth: 46, editFontSize: 14, settingsWidth: 44, settingsFontSize: 18, pillHeight: 41, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 44)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(editWidth: 49, editFontSize: 15, settingsWidth: 47, settingsFontSize: 20, pillHeight: 44, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 47)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(editWidth: 50, editFontSize: 16, settingsWidth: 48, settingsFontSize: 20, pillHeight: 45, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 48)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(editWidth: 64, editFontSize: 20, settingsWidth: 62, settingsFontSize: 26, pillHeight: 56, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 62, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 80)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(editWidth: 74, editFontSize: 23, settingsWidth: 72, settingsFontSize: 30, pillHeight: 64, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 72, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 90)
        }
    }

    // MARK: - Feed Format Per Screen Size
    /// Tunable sizing for the main feed (profile header, bio, and submissions).
    /// - `contentPadding`: padding around the whole scroll content.
    /// - `sectionSpacing`: gap between header, bio, divider, and submissions.
    /// - `rowSpacing`: gap between submission rows.
    /// - `profileImageSize`: diameter of the circular profile photo.
    /// - `thumbnailWidth`: width of each submission's thumbnail.
    private struct FeedFormat {
        var contentPadding: CGFloat
        var sectionSpacing: CGFloat
        var rowSpacing: CGFloat
        var profileImageSize: CGFloat
        var thumbnailWidth: CGFloat
    }

    /// Adjust the values in each case to tune the feed for that screen size.
    private var feedFormat: FeedFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return FeedFormat(contentPadding: 16, sectionSpacing: 16, rowSpacing: 12, profileImageSize: 72, thumbnailWidth: 100)
        case .size402x874: // iPhone 16 Pro, 17
            return FeedFormat(contentPadding: 16, sectionSpacing: 16, rowSpacing: 12, profileImageSize: 74, thumbnailWidth: 102)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return FeedFormat(contentPadding: 17, sectionSpacing: 17, rowSpacing: 13, profileImageSize: 78, thumbnailWidth: 109)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return FeedFormat(contentPadding: 18, sectionSpacing: 18, rowSpacing: 13, profileImageSize: 81, thumbnailWidth: 112)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return FeedFormat(contentPadding: 40, sectionSpacing: 24, rowSpacing: 18, profileImageSize: 110, thumbnailWidth: 150)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return FeedFormat(contentPadding: 80, sectionSpacing: 28, rowSpacing: 20, profileImageSize: 128, thumbnailWidth: 175)
        }
    }

    // ORANGE HEADER
    private var topBar: some View {
        ZStack {
            Color.brandOrange
                .ignoresSafeArea(edges: .top)
                .frame(height: toolbarFormat.barHeight)
            HStack(spacing: 0) {
                Image("Portfolio")
                    .resizable()
                    .scaledToFill()
                    .frame(height: toolbarFormat.logoHeight)
                    .offset(x: toolbarFormat.logoOffsetX, y: toolbarFormat.logoOffsetY)
                Spacer(minLength: 8)
                filterPill
            }
            .frame(height: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // TOOLBAR PILLS (distinct buttons with space between them)
    private var filterPill: some View {
        HStack(spacing: 4) {
            Button {
                showingLogin = true
            } label: {
                Text(displayName == "Your Name" ? "Edit" : "Edit")
                    .font(.system(size: toolbarFormat.editFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: toolbarFormat.pillLength ?? toolbarFormat.editWidth, height: toolbarFormat.pillHeight)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(Color.pillActive))
            .offset(x: toolbarFormat.pillOffsetX, y: toolbarFormat.pillOffsetY)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: toolbarFormat.settingsFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: toolbarFormat.settingsWidth, height: toolbarFormat.pillHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(Color.pillActive))
            .offset(x: toolbarFormat.pillOffsetX, y: toolbarFormat.pillOffsetY)
        }
    }
    
    private var editProfileSheet: some View {
        EditProfileSheet(
            selectedItem: $selectedItem,
            tempFirstName: $tempFirstName,
            tempLastName: $tempLastName,
            tempYear: $tempYear,
            tempUserTypes: $tempUserTypes,
            tempBio: $tempBio,
            tempMajor: $tempMajor,
            tempMinor: $tempMinor,
            tempCertificate: $tempCertificate,
            tempHometown: $tempHometown,
            tempImageData: $tempImageData,
            tempImageOffsetX: $tempImageOffsetX,
            tempImageOffsetY: $tempImageOffsetY,
            tempImageScale: $tempImageScale,
            showImageAdjustment: $showImageAdjustment,
            imageWasRemoved: $imageWasRemoved,
            profileImage: profileImage,
            onSave: {
                // Save to new storage format
                userFirstName = tempFirstName
                userLastName = tempLastName
                userGraduationYear = tempYear
                userType = tempUserTypes.sorted().joined(separator: ", ")
                userBio = tempBio
                userMajor = tempMajor
                userMinor = tempMinor
                userCertificate = tempCertificate
                userHometown = tempHometown

                // Also save to legacy format for compatibility
                profileName = "\(tempFirstName) \(tempLastName)".trimmingCharacters(in: .whitespaces)
                graduationYear = Int(tempYear) ?? 0

                // Handle profile image - save or remove
                if imageWasRemoved {
                    // User explicitly removed the photo
                    profileImageData = Data()
                    profileImageOffsetX = 0
                    profileImageOffsetY = 0
                    profileImageScale = 1.0

                    // Also remove from documents directory
                    if let imagePath = UserDefaults.standard.string(forKey: "profileImagePath") {
                        try? FileManager.default.removeItem(atPath: imagePath)
                        UserDefaults.standard.removeObject(forKey: "profileImagePath")
                    }
                } else if let newImageData = tempImageData, let original = UIImage(data: newImageData) {
                    // Bake the pan/zoom crop into the image so the framing is saved
                    // with the photo and travels to CloudKit / the directory / other
                    // users. Reset the crop to identity so it isn't applied twice.
                    let baked = ProfileImageCropper.bakedImage(
                        from: original,
                        scale: CGFloat(tempImageScale),
                        offsetX: CGFloat(tempImageOffsetX),
                        offsetY: CGFloat(tempImageOffsetY)
                    )
                    profileImageData = baked.jpegData(compressionQuality: 0.9) ?? newImageData
                    saveImageToDocuments(baked)
                    profileImageOffsetX = 0
                    profileImageOffsetY = 0
                    profileImageScale = 1.0
                }
                // If neither condition is true, keep the existing photo
                
                // Save to CloudKit for visibility in directory
                Task {
                    await saveProfileToCloudKit()
                }
                
                showingLogin = false
            },
            onAppear: {
                tempFirstName = userFirstName
                tempLastName = userLastName
                tempYear = userGraduationYear.isEmpty ? String(Calendar.current.component(.year, from: .now)) : userGraduationYear
                tempUserTypes = Set(userType.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                tempBio = userBio
                tempMajor = userMajor
                tempMinor = userMinor
                tempCertificate = userCertificate
                tempHometown = userHometown
                tempImageOffsetX = profileImageOffsetX
                tempImageOffsetY = profileImageOffsetY
                tempImageScale = profileImageScale
                imageWasRemoved = false // Reset flag when opening edit sheet
                
                // Load existing image data
                if !profileImageData.isEmpty {
                    tempImageData = profileImageData
                } else if let profileImage {
                    tempImageData = profileImage.jpegData(compressionQuality: 0.8)
                }
                
                selectedItem = nil
            }
        )
    }
    

    
    private func applyAppearanceMode() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        guard let window = windowScene.windows.first else { return }
        
        let newStyle: UIUserInterfaceStyle
        switch appearanceMode {
        case "light":
            newStyle = .light
        case "dark":
            newStyle = .dark
        case "automatic":
            newStyle = .unspecified
        default:
            newStyle = .unspecified
        }
        
        // Apply without an animated window cross-dissolve — this runs on every tab
        // switch to Portfolio, and animating it made the tab transition look
        // different from the other tabs.
        window.overrideUserInterfaceStyle = newStyle
    }

    private func saveImageToDocuments(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imageURL = documentsPath.appendingPathComponent("profileImage.jpg")
        
        try? data.write(to: imageURL)
        
        // Store the path in UserDefaults
        UserDefaults.standard.set(imageURL.path, forKey: "profileImagePath")
    }
    
    private func saveProfileToCloudKit() async {
        guard await CloudKitManager.shared.isAvailable else {
            print("⚠️ CloudKit not available - profile saved locally only")
            return
        }
        
        do {
            guard let userRecordID = await CloudKitManager.shared.userRecordID else {
                print("⚠️ No user record ID available")
                return
            }
            
            let recordID = CKRecord.ID(recordName: "UserProfile_\(userRecordID.recordName)")
            let record = CKRecord(recordType: "UserProfile", recordID: recordID)
            
            // Save profile data
            record["firstName"] = userFirstName as CKRecordValue
            record["lastName"] = userLastName as CKRecordValue
            record["major"] = userMajor as CKRecordValue
            record["minor"] = userMinor as CKRecordValue
            record["certificate"] = userCertificate as CKRecordValue
            record["graduationYear"] = userGraduationYear as CKRecordValue
            record["userTypes"] = userType as CKRecordValue
            record["bio"] = userBio as CKRecordValue
            record["hometown"] = userHometown as CKRecordValue
            
            // Save profile image if available
            if !profileImageData.isEmpty,
               let image = UIImage(data: profileImageData),
               let imageData = image.jpegData(compressionQuality: 0.8) {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("profile_\(userRecordID.recordName).jpg")
                try imageData.write(to: tempURL)
                let asset = CKAsset(fileURL: tempURL)
                record["profileImage"] = asset
            }
            
            try await CloudKitManager.shared.save(record: record)
            print("✅ User profile saved to CloudKit: \(displayName)")
        } catch {
            print("❌ Failed to save profile to CloudKit: \(error.localizedDescription)")
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Binding var appearanceMode: String
    @Binding var isModeratorMode: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @Namespace private var namespace
    @State private var showLogoutConfirmation = false
    @State private var showSavedCollections = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    
    // Get current user name
    @AppStorage("userFirstName") private var userFirstName: String = ""
    @AppStorage("userLastName") private var userLastName: String = ""
    
    private var currentUserName: String {
        "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
    }
    
    private var isAidenWeinstein: Bool {
        currentUserName == "Aiden Weinstein"
    }
    
    enum AppearanceOption: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"
        case automatic = "Auto"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            case .automatic: return "circle.lefthalf.filled"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SavedCollectionsView()
                    } label: {
                        HStack {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(Color.utBrandOrange)
                            Text("Saved Collections")
                        }
                    }
                } header: {
                    Text("Library")
                }
                
                Section {
                    HStack(spacing: 0) {
                        ForEach(AppearanceOption.allCases) { option in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    appearanceMode = option.rawValue.lowercased()
                                    applyAppearanceMode()
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: option.icon)
                                        .font(.system(size: 18, weight: .medium))
                                    Text(option.rawValue)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(appearanceMode == option.rawValue.lowercased() ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 70)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background {
                                if appearanceMode == option.rawValue.lowercased() {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.utBrandOrange)
                                        .padding(3)
                                        .matchedGeometryEffect(id: "appearancePill", in: namespace)
                                }
                            }
                        }
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            // ====== UI CONTROLS!!!!! ======
                            // Fixed dark mode glitch - using proper adaptive background
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                            // ==============================
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } header: {
                    Text("Display")
                }
                
                // Only show moderator mode for Aiden Weinstein
                if isAidenWeinstein {
                    Section {
                        Toggle(isOn: $isModeratorMode) {
                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(.secondary)
                                Text("Moderator Mode")
                            }
                        }
                    } header: {
                        Text("Access")
                    }
                }
                
                // Feedback Section
                Section {
                    NavigationLink {
                        FeedbackSubmissionView()
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .foregroundStyle(.secondary)
                            Text("Feedback")
                        }
                    }
                } header: {
                    Text("Help Us Improve")
                }
                
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Log Out")
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        HStack {
                            if isDeletingAccount {
                                ProgressView()
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "person.crop.circle.badge.xmark")
                            }
                            Text("Delete Account")
                        }
                    }
                    .disabled(isDeletingAccount)
                } header: {
                    Text("Account")
                } footer: {
                    Text("Permanently deletes your profile from the directory. Your posts are not removed.")
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemBackground)) // opaque sheet, no transparency
        .alert("Are you sure?", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
                .foregroundStyle(.secondary)
            Button("Log Out", role: .destructive) {
                logOut()
            }
        } message: {
            Text("You will be logged out and returned to the welcome screen.")
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Account", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("This permanently removes your profile from Longhorn Artists Connect and returns you to the welcome screen. This can't be undone.")
        }
    }

    private func logOut() {
        // Clear user session but keep account data
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        dismiss()
    }

    /// Permanently deletes the user's profile from CloudKit and clears all local
    /// account data, returning them to onboarding.
    private func deleteAccount() {
        isDeletingAccount = true
        let profile = UserProfileModel()
        Task {
            // Remove the UserProfile record (keyed to this iCloud account) from CloudKit.
            await profile.deleteFromCloudKit()

            await MainActor.run {
                // Wipe all local account data and reset onboarding.
                profile.clearAll()
                isDeletingAccount = false
                dismiss()
            }
        }
    }
    
    private func applyAppearanceMode() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        guard let window = windowScene.windows.first else { return }
        
        let newStyle: UIUserInterfaceStyle
        switch appearanceMode {
        case "light":
            newStyle = .light
        case "dark":
            newStyle = .dark
        case "automatic":
            newStyle = .unspecified
        default:
            newStyle = .unspecified
        }
        
        // Animate the transition
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
            window.overrideUserInterfaceStyle = newStyle
        }
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var tempFirstName: String
    @Binding var tempLastName: String
    @Binding var tempYear: String
    @Binding var tempUserTypes: Set<String>
    @Binding var tempBio: String
    @Binding var tempMajor: String
    @Binding var tempMinor: String
    @Binding var tempCertificate: String
    @Binding var tempHometown: String
    @Binding var tempImageData: Data?
    @Binding var tempImageOffsetX: Double
    @Binding var tempImageOffsetY: Double
    @Binding var tempImageScale: Double
    @Binding var showImageAdjustment: Bool
    @Binding var imageWasRemoved: Bool
    
    let profileImage: UIImage?
    let onSave: () -> Void
    let onAppear: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showYearPicker = false
    @State private var showMajorPicker = false
    @State private var showMinorPicker = false
    @State private var showCertificatePicker = false
    @State private var showTagsPicker = false

    private let availableYears = Array(2016...2036).map { String($0) }

    /// A tappable academic row (Major/Minor/Certificate) showing the selected
    /// value (or "Select" when empty) followed by a single orange chevron.
    @ViewBuilder
    private func academicRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if value.isEmpty {
                Text("Select")
                    .foregroundStyle(Color.utBrandOrange)
            } else {
                Text(value)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(value.isEmpty ? Color.utBrandOrange : Color.secondary)
        }
        .contentShape(Rectangle())
    }

    var body: some View {
        NavigationStack {
            Form {
                // Profile Photo Section - compact and centered at top
                Section {
                    VStack(spacing: 12) {
                        // Profile photo centered
                        if let imageData = tempImageData, let uiImage = UIImage(data: imageData) {
                            Group {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .scaleEffect(tempImageScale)
                                    // Offsets are saved in the adjuster's 300pt preview
                                    // space, so scale them to this 100pt frame to match.
                                    .offset(x: CGFloat(tempImageOffsetX) * 100 / ImageAdjustmentView.previewSize,
                                            y: CGFloat(tempImageOffsetY) * 100 / ImageAdjustmentView.previewSize)
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            }
                            .frame(width: 100, height: 100)
                        } else if !imageWasRemoved, let currentImage = profileImage {
                            Group {
                                Image(uiImage: currentImage)
                                    .resizable()
                                    .scaledToFill()
                                    .scaleEffect(tempImageScale)
                                    // Offsets are saved in the adjuster's 300pt preview
                                    // space, so scale them to this 100pt frame to match.
                                    .offset(x: CGFloat(tempImageOffsetX) * 100 / ImageAdjustmentView.previewSize,
                                            y: CGFloat(tempImageOffsetY) * 100 / ImageAdjustmentView.previewSize)
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            }
                            .frame(width: 100, height: 100)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 100))
                                .foregroundStyle(.secondary)
                                .frame(width: 100, height: 100)
                        }
                        
                        // Buttons horizontally centered
                        HStack(spacing: 12) {
                            // Choose or Adjust Photo button
                            if tempImageData != nil || (profileImage != nil && !imageWasRemoved) {
                                // Show Adjust button when there's a photo
                                Button {
                                    showImageAdjustment = true
                                } label: {
                                    Text("Adjust Photo")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(UIColor.secondarySystemGroupedBackground))
                                        .foregroundStyle(.primary)
                                        .clipShape(Capsule())
                                }
                                
                                // Show Remove button when there's a photo
                                Button {
                                    tempImageData = nil
                                    tempImageOffsetX = 0
                                    tempImageOffsetY = 0
                                    tempImageScale = 1.0
                                    selectedItem = nil
                                    imageWasRemoved = true
                                } label: {
                                    Text("Remove")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.red)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            } else {
                                // Show Choose button when there's no photo
                                PhotosPicker(selection: $selectedItem, matching: .images) {
                                    Text("Choose Photo")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.utBrandOrange)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                
                // Basic Information
                Section("Basic Information") {
                    TextField("Name", text: Binding(
                        get: {
                            if !tempFirstName.isEmpty || !tempLastName.isEmpty {
                                return "\(tempFirstName) \(tempLastName)".trimmingCharacters(in: .whitespaces)
                            }
                            return ""
                        },
                        set: { newValue in
                            // Split the name into first and last name
                            let components = newValue.split(separator: " ", maxSplits: 1)
                            if components.count >= 1 {
                                tempFirstName = String(components[0])
                            } else {
                                tempFirstName = ""
                            }
                            if components.count >= 2 {
                                tempLastName = String(components[1])
                            } else {
                                tempLastName = ""
                            }
                        }
                    ))
                    .autocorrectionDisabled()
                    
                    Button {
                        showYearPicker = true
                    } label: {
                        HStack {
                            Text("Class of")
                                .foregroundStyle(.primary)
                            Spacer()
                            if tempYear.isEmpty {
                                Text("Select")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(tempYear)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    TextField("Bio", text: $tempBio, axis: .vertical)
                        .lineLimit(3...6)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                
                // Academic Information
                Section("Academic") {
                    Button {
                        showMajorPicker = true
                    } label: {
                        academicRow(title: "Major", value: tempMajor)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showMinorPicker = true
                    } label: {
                        academicRow(title: "Minor", value: tempMinor)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showCertificatePicker = true
                    } label: {
                        academicRow(title: "Certificate", value: tempCertificate)
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                
                // Tags
                Section("Tags") {
                    Button {
                        showTagsPicker = true
                    } label: {
                        HStack {
                            Text("Tags")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("Add")
                                .foregroundStyle(Color.utBrandOrange)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.utBrandOrange)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showMajorPicker) {
                MajorSelectionView(selectedMajor: $tempMajor)
            }
            .navigationDestination(isPresented: $showMinorPicker) {
                MinorSelectionView(selectedMinor: $tempMinor)
            }
            .navigationDestination(isPresented: $showCertificatePicker) {
                CertificateSelectionView(selectedCertificate: $tempCertificate)
            }
            .navigationDestination(isPresented: $showTagsPicker) {
                TagsSelectionView(selectedTags: $tempUserTypes)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .disabled(tempFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                             tempYear.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .onAppear {
            onAppear()
        }
        .onChange(of: selectedItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        tempImageData = data
                        tempImageOffsetX = 0
                        tempImageOffsetY = 0
                        tempImageScale = 1.0
                        imageWasRemoved = false // Reset flag when new photo is chosen
                        // Automatically show adjustment view after choosing photo
                        showImageAdjustment = true
                    }
                }
            }
        }
        .sheet(isPresented: $showImageAdjustment) {
            if let imageData = tempImageData ?? (profileImage?.jpegData(compressionQuality: 0.8)) {
                ImageAdjustmentView(
                    imageData: imageData,
                    offsetX: $tempImageOffsetX,
                    offsetY: $tempImageOffsetY,
                    scale: $tempImageScale
                )
            }
        }
        .sheet(isPresented: $showYearPicker) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        showYearPicker = false
                    }
                    .foregroundStyle(Color.utBrandOrange)
                    
                    Spacer()
                    
                    Text("Class of")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("Done") {
                        showYearPicker = false
                    }
                    .foregroundStyle(Color.utBrandOrange)
                    .fontWeight(.semibold)
                }
                .padding()
                
                Divider()
                
                // Picker
                Picker("Year", selection: $tempYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(year).tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            }
            .presentationDetents([.height(300)])
        }
    }
}

// MARK: - Image Adjustment View

struct ImageAdjustmentView: View {
    /// Diameter of the adjuster's preview circle. The saved `offsetX`/`offsetY`
    /// are in points relative to this size, so every display that shows the
    /// cropped photo must scale the offset by (its diameter / previewSize) to
    /// reproduce the exact same framing. See `profileImageView` / onboarding.
    static let previewSize: CGFloat = 300

    let imageData: Data
    @Binding var offsetX: Double
    @Binding var offsetY: Double
    @Binding var scale: Double
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentScale: CGFloat = 1.0
    @State private var currentOffsetX: CGFloat = 0
    @State private var currentOffsetY: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview area
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: Self.previewSize, height: Self.previewSize)

                    Circle()
                        .strokeBorder(Color.utBrandOrange, lineWidth: 3)
                        .frame(width: Self.previewSize, height: Self.previewSize)

                    if let uiImage = UIImage(data: imageData) {
                        GeometryReader { geometry in
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .scaleEffect(currentScale)
                                .offset(x: currentOffsetX, y: currentOffsetY)
                                .frame(width: Self.previewSize, height: Self.previewSize)
                                .clipShape(Circle())
                        }
                        .frame(width: Self.previewSize, height: Self.previewSize)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    currentOffsetX = offsetX + value.translation.width
                                    currentOffsetY = offsetY + value.translation.height
                                }
                                .onEnded { _ in
                                    offsetX = currentOffsetX
                                    offsetY = currentOffsetY
                                }
                        )
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let newScale = scale * value
                                    currentScale = max(1.0, newScale) // Prevent zooming out below 1.0
                                }
                                .onEnded { _ in
                                    scale = max(1.0, currentScale)
                                }
                        )
                    }
                }
                .padding()
                
                // Zoom slider
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                            .foregroundStyle(.secondary)
                        
                        Slider(value: $currentScale, in: 1.0...3.0) { editing in
                            if !editing {
                                scale = currentScale
                            }
                        }
                        
                        Image(systemName: "plus.magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    Text("Zoom: \(Int(currentScale * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Reset button
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        currentOffsetX = 0
                        currentOffsetY = 0
                        currentScale = 1.0
                        offsetX = 0
                        offsetY = 0
                        scale = 1.0
                    }
                } label: {
                    Label("Reset Position", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .navigationTitle("Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Revert to original values
                        currentOffsetX = offsetX
                        currentOffsetY = offsetY
                        currentScale = scale
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Save the current adjustments
                        offsetX = currentOffsetX
                        offsetY = currentOffsetY
                        scale = currentScale
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                currentOffsetX = offsetX
                currentOffsetY = offsetY
                currentScale = scale
            }
        }
    }
}

// MARK: - Flow Layout for Role Bubbles

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            var currentRow: [Int] = []

            // Shifts the items in the just-completed row so the row is horizontally
            // centered within maxWidth.
            func centerCurrentRow() {
                guard !currentRow.isEmpty else { return }
                let rowWidth = x - spacing // trailing spacing was added after the last item
                let offset = max(0, (maxWidth - rowWidth) / 2)
                for i in currentRow {
                    frames[i].origin.x += offset
                }
            }

            var index = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    centerCurrentRow()
                    currentRow = []
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                currentRow.append(index)
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
                index += 1
            }
            centerCurrentRow()

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// MARK: - Saved Collections View

struct SavedCollectionsView: View {
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @State private var selectedCollection: PostCollection?
    
    var body: some View {
        List {
            // Liked collection always first
            if let likedCollection = store.collections.first(where: { $0.isSystemCollection && $0.name == "Liked" }) {
                NavigationLink(destination: CollectionDetailView(collection: likedCollection)) {
                    CollectionRow(collection: likedCollection)
                }
            }
            
            // User collections
            ForEach(store.collections.filter { !$0.isSystemCollection }) { collection in
                NavigationLink(destination: CollectionDetailView(collection: collection)) {
                    CollectionRow(collection: collection)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        store.deleteCollection(collection)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Saved Collections")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CollectionRow: View {
    let collection: PostCollection
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    
    var actualSubmissions: [Submission] {
        store.getSubmissions(for: collection)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: collection.isSystemCollection ? "heart.fill" : "bookmark.fill")
                .font(.title2)
                .foregroundStyle(collection.isSystemCollection ? .red : .brandOrange)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.headline)
                Text("\(actualSubmissions.count) \(actualSubmissions.count == 1 ? "item" : "items")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct CollectionDetailView: View {
    let collection: PostCollection
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @State private var selectedSubmission: Submission?
    @State private var liked = false
    
    var submissions: [Submission] {
        store.getSubmissions(for: collection)
    }
    
    var body: some View {
        ScrollView {
            if submissions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: collection.isSystemCollection ? "heart" : "bookmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No items in this collection")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Save posts to see them here")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(submissions) { submission in
                        Button {
                            selectedSubmission = submission
                        } label: {
                            CollectionItemCard(submission: submission)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSubmission) { submission in
            ProjectDetailView(post: submission, liked: $liked)
        }
    }
}

struct CollectionItemCard: View {
    let submission: Submission
    
    private var tintColor: Color {
        let colors: [Color] = [.orange, .purple, .blue, .teal, .indigo, .pink, .mint, .cyan]
        let hash = abs(submission.title.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnailData = submission.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 60)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: [tintColor.opacity(0.55), tintColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 100, height: 60)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: submission.type == .film ? "film" : "music.note")
                            .foregroundStyle(.white.opacity(0.9))
                    )
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(submission.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Text("by \(submission.submittedBy)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(submission.type.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(tintColor.opacity(0.2))
                    .foregroundStyle(tintColor)
                    .clipShape(Capsule())
            }
            
            Spacer()
        }
        .padding(12)
        // ====== UI CONTROLS!!!!! ======
        // Fixed dark mode glitch - using proper adaptive background
        .background(Color(UIColor.secondarySystemGroupedBackground))
        // ==============================
        .cornerRadius(12)
    }
}

// MARK: - Major Selection View

struct MajorSelectionView: View {
    @Binding var selectedMajor: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSchool: String?
    
    let schools: [(name: String, majors: [String])] = [
        ("Cockrell School of Engineering", [
            "Petroleum Engineering",
            "Chemical Engineering",
            "Civil Engineering",
            "Environmental Engineering",
            "Aerospace/Aeronautical/Astronautical Engineering",
            "Computer Engineering",
            "Electrical/Electronic/Communications Engineering",
            "Bioengineering/Biomedical Engineering",
            "Mechanical Engineering"
        ]),
        ("College of Education", [
            "All-Level Special Education",
            "Bilingual Core Subjects/Generalist",
            "English as a Second Language Generalist",
            "Youth and Community Studies",
            "Applied Movement Science",
            "Exercise Science",
            "Health Promotion & Behavioral Science",
            "Physical Culture & Sports",
            "Sports Management"
        ]),
        ("College of Fine Arts", [
            "Acting",
            "Arts and Entertainment Technologies",
            "Art Education",
            "Art History",
            "Dance",
            "Design",
            "Jazz",
            "Music",
            "Music Composition",
            "Music Studies (Music Education)",
            "Music Performance",
            "Studio Art",
            "Theatre and Dance",
            "Theatre Education"
        ]),
        ("College of Liberal Arts", [
            "African and African Diaspora Studies",
            "American Studies",
            "Anthropology",
            "Asian American Studies",
            "Asian Cultures and Languages",
            "Asian Studies",
            "Behavioral & Social Data Sciences",
            "Classical Languages",
            "Classical Studies",
            "Economics",
            "English",
            "Environmental Science",
            "European Studies",
            "French Studies",
            "Geography",
            "German",
            "Government",
            "Health and Society",
            "History",
            "Human Dimensions of Organizations",
            "Humanities",
            "International Relations and Global Studies",
            "Italian Studies",
            "Jewish Studies",
            "Latin American Studies",
            "Linguistics",
            "Mexican American and Latina/o Studies",
            "Middle Eastern Studies",
            "Philosophy",
            "Plan II Honors Program",
            "Psychology",
            "Race, Indigeneity, and Migration",
            "Religious Studies",
            "Rhetoric and Writing",
            "Russian, East European and Eurasian Studies",
            "Sociology",
            "Spanish",
            "Sustainability Studies",
            "Urban Studies",
            "Women's and Gender Studies"
        ]),
        ("College of Natural Sciences", [
            "Astronomy",
            "Biochemistry",
            "Biology",
            "Chemistry",
            "Computer Science",
            "Environmental Science",
            "Human Development and Family Sciences",
            "Mathematics",
            "Medical Laboratory Science",
            "Neuroscience",
            "Nutrition",
            "Physics",
            "Public Health",
            "Statistics and Data Science",
            "Textiles and Apparel"
        ]),
        ("College of Pharmacy", [
            "Doctorate of Pharmacy"
        ]),
        ("Dell Medical School", [
            "Child Neurology",
            "Dermatology",
            "Emergency Medicine",
            "Family Medicine",
            "Internal Medicine",
            "Neurological Surgery",
            "Neurology (Ascension Seton)",
            "Neurology (Dell Seton)",
            "Obstetrics & Gynecology",
            "Ophthalmology",
            "Orthopaedic Surgery",
            "Pediatrics",
            "Physical Medicine & Rehabilitation",
            "Psychiatry",
            "Radiology",
            "Surgery",
            "Transitional"
        ]),
        ("Jackson School of Geosciences", [
            "Climate System Science",
            "Environmental Science",
            "General Geology",
            "Geophysics",
            "Hydrology & Water Resources",
            "Teaching",
            "Geosystems Engineering",
            "Geological Sciences"
        ]),
        ("LBJ School of Public Affairs", [
            "Public Affairs",
            "Global Policy Studies",
            "Master of National Security",
            "Public Leadership",
            "Public Policy"
        ]),
        ("McCombs School of Business", [
            "Accounting",
            "Finance",
            "International Business",
            "Marketing",
            "Business Analytics",
            "Canfield Business Honors Program",
            "Integrated MPA",
            "Management",
            "Management Information Systems",
            "Supply Chain Management"
        ]),
        ("Moody College of Communication", [
            "Journalism",
            "Science in Advertising",
            "Communication & Leadership",
            "Communication Studies",
            "Science in Public Relations",
            "Radio-Television-Film",
            "Speech, Language, and Hearing Sciences"
        ]),
        ("School of Architecture", [
            "Architecture",
            "Science in Architectural Studies"
        ]),
        ("School of Civic Leadership", [
            "Civic Honors"
        ]),
        ("School of Information", [
            "Human-Centered Data Science",
            "User Experience (UX) Design",
            "Social Justice Informatics",
            "Health Informatics",
            "Cultural Heritage Informatics",
            "Social Informatics"
        ]),
        ("School of Law", [
            "Advocacy Program",
            "AI Innovation & Law Program",
            "Law & Business Program",
            "Law & Philosophy Program",
            "Private Law Theory Program",
            "Richard & Ginni Mithoff Pro Bono Program"
        ]),
        ("School of Nursing", [
            "Bachelor of Science in Nursing"
        ]),
        ("School of Social Work", [
            "Bachelor of Social Work"
        ])
    ]
    
    var body: some View {
        if let school = selectedSchool {
            // Show majors for selected school
            MajorListView(
                schoolName: school,
                majors: schools.first(where: { $0.name == school })?.majors ?? [],
                selectedMajor: $selectedMajor,
                onBack: { selectedSchool = nil }
            )
        } else {
            // Show list of schools
            List {
                ForEach(schools, id: \.name) { school in
                    Button {
                        selectedSchool = school.name
                    } label: {
                        HStack {
                            Text(school.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Major")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MajorListView: View {
    let schoolName: String
    let majors: [String]
    @Binding var selectedMajor: String
    let onBack: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(majors, id: \.self) { major in
                Button {
                    selectedMajor = major
                    dismiss()
                } label: {
                    HStack {
                        Text(major)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedMajor == major {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(schoolName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(schoolName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
    }
}

// MARK: - Minor Selection View

struct MinorSelectionView: View {
    @Binding var selectedMinor: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSchool: String?
    
    let schools: [(name: String, minors: [String])] = [
        ("School of Architecture", [
            "Architectural History",
            "Architectural Studies",
            "Interior Design",
            "Landscape Studies"
        ]),
        ("McCombs School of Business", [
            "Accounting",
            "Accounting for Business Economics Option Program",
            "Analytics and the Business of Sports",
            "Business Analytics",
            "Business and Public Policy",
            "Business Foundations",
            "Energy Management",
            "Entrepreneurship",
            "Finance",
            "Finance for Business Economics Option Program",
            "Global Management",
            "Health Care Reform and Innovation",
            "International Business",
            "Leadership in Global Sustainability",
            "Management",
            "Management Information Systems",
            "Marketing",
            "National Security and International Business",
            "Professional Sales and Business Development",
            "Real Estate",
            "Risk Management",
            "Supply Chain Management",
            "Wealth Management"
        ]),
        ("School of Civic Leadership", [
            "Civics"
        ]),
        ("Moody College of Communication", [
            "Communicating for Development and Philanthropy",
            "Communicating Social Issues",
            "Communication Studies",
            "Global Communication",
            "Health Communication",
            "Journalism and Media",
            "Latino Media Arts and Studies",
            "Leadership in Global Sustainability",
            "Media and Entertainment Industries",
            "Media Studies",
            "Professional Sales and Business Development",
            "Science Communication",
            "Sports Media",
            "Sports Production and Broadcasting"
        ]),
        ("College of Education", [
            "Educational Psychology",
            "Kinesiology and Health Education",
            "Urban Teachers"
        ]),
        ("Cockrell School of Engineering", [
            "Materials Science and Engineering",
            "Robotics",
            "Semiconductor Science and Engineering",
            "Sustainable Energy"
        ]),
        ("College of Fine Arts", [
            "Art History",
            "Arts Management and Administration",
            "Studio Art"
        ]),
        ("Jackson School of Geosciences", [
            "Computational Geosciences",
            "Geosciences",
            "Hydrology",
            "Sedimentology and Earth Surface Processes"
        ]),
        ("School of Information", [
            "Informatics"
        ]),
        ("College of Liberal Arts", [
            "African and African Diaspora Studies",
            "American Sign Language Studies",
            "American Studies",
            "Anthropology",
            "Applied Economics",
            "Arabic",
            "Archaeology",
            "Asian American Studies",
            "Asian Religions",
            "Bengali",
            "Chinese",
            "Classical Studies",
            "Comparative Literature",
            "Core Texts and Ideas",
            "Creative Writing in Spanish",
            "Cultural Anthropology",
            "Cultural Expression, Human Experience, and Thought",
            "Economics",
            "English",
            "European Studies",
            "Evolutionary and Functional Anatomy",
            "French Studies",
            "Geography",
            "German, Scandinavian, and Dutch Studies",
            "Global Interreligious Dynamics",
            "Government",
            "Greek",
            "Hebrew",
            "Hindi",
            "History",
            "Holocaust and Genocide Studies",
            "Italian Studies",
            "Jewish Studies",
            "Korean",
            "Language, Culture, and Communication",
            "Latin",
            "Law and Religion",
            "Law, Justice, and Society",
            "Lesbian, Gay, Bisexual, Transgender, and Queer/Sexualities Studies",
            "Malayalam",
            "Medieval Studies",
            "Mexican American and Latina/o Studies",
            "Middle Eastern Studies",
            "Military Leadership",
            "Persian",
            "Philosophy",
            "Philosophy of Law",
            "Philosophy of the Mind and Language",
            "Philosophy, Politics, and Economics",
            "Portuguese",
            "Primatology",
            "Religious Studies",
            "Rhetoric and Writing",
            "Russian",
            "Russian, East European, and Eurasian Studies",
            "Sanskrit",
            "Slavic and Eurasian Languages",
            "Social and Behavioral Sciences",
            "Sociology",
            "Spanish",
            "Tamil",
            "Turkish",
            "Ukrainian",
            "Urban Studies",
            "Urdu",
            "UTeach-Liberal Arts",
            "Women's and Gender Studies"
        ]),
        ("College of Natural Sciences", [
            "Fashion and Consumer Science",
            "Robotics",
            "Statistics and Data Science"
        ]),
        ("School of Social Work", [
            "Critical Disability Studies",
            "Social Work"
        ])
    ]
    
    var body: some View {
        if let school = selectedSchool {
            // Show minors for selected school
            MinorListView(
                schoolName: school,
                minors: schools.first(where: { $0.name == school })?.minors ?? [],
                selectedMinor: $selectedMinor,
                onBack: { selectedSchool = nil }
            )
        } else {
            // Show list of schools
            List {
                // None option at the top
                Button {
                    selectedMinor = ""
                    dismiss()
                } label: {
                    HStack {
                        Text("None")
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedMinor.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                }
                .buttonStyle(.plain)

                // School list
                ForEach(schools, id: \.name) { school in
                    Button {
                        selectedSchool = school.name
                    } label: {
                        HStack {
                            Text(school.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Minor")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MinorListView: View {
    let schoolName: String
    let minors: [String]
    @Binding var selectedMinor: String
    let onBack: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach(minors, id: \.self) { minor in
                Button {
                    selectedMinor = minor
                    dismiss()
                } label: {
                    HStack {
                        Text(minor)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedMinor == minor {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(schoolName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(schoolName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
    }
}

// MARK: - Certificate Selection View

struct CertificateSelectionView: View {
    @Binding var selectedCertificate: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSchool: String?
    
    let schools: [(name: String, certificates: [String])] = [
        ("Undergraduate College", [
            "Children and Society",
            "Conflict Resolution and Peace Studies",
            "Criminal Law, Justice, and Inequality",
            "Design Strategies",
            "Digital Arts and Media",
            "Environment and Sustainability",
            "Ethics and Leadership in Business",
            "Ethics and Leadership in Health Care",
            "Ethics and Leadership in Law, Politics, and Government",
            "Human Rights and Social Justice",
            "Innovation, Creativity, and Entrepreneurship",
            "Museum Studies",
            "Nonprofits and Social Entrepreneurship",
            "Patients, Practitioners, and Cultures of Care",
            "Public Policy",
            "Smart Cities",
            "Social Inequality, Health, and Policy"
        ]),
        ("McCombs School of Business", [
            "Elements of Business"
        ]),
        ("Cockrell School of Engineering", [
            "Computational Science and Engineering",
            "Humanitarian Engineering",
            "National Academy of Engineering Grand Challenges Scholars Program"
        ]),
        ("Jackson School of Geosciences", [
            "Computational Science and Engineering"
        ]),
        ("School of Information", [
            "Digital Humanities"
        ]),
        ("College of Liberal Arts", [
            "African Studies",
            "Business Spanish",
            "Computational Science and Engineering",
            "Core Texts and Ideas",
            "Creative Writing",
            "Creative Writing Honors",
            "Digital Humanities",
            "German",
            "History and Philosophy of Science",
            "Indigenous Studies",
            "Japanese",
            "Lesbian, Gay, Bisexual, Transgender, and Queer/Sexualities Studies",
            "Security Studies",
            "Spanish for Medical Professions",
            "Spanish for Mental Health Professions"
        ]),
        ("College of Natural Sciences", [
            "Advanced Mathematics",
            "Applied Statistical Modeling",
            "Computational Science and Engineering",
            "Programming and Computation",
            "Evidence and Inquiry",
            "Food and Society",
            "Forensic Science",
            "Marine Science",
            "Pre-Health Professions",
            "Quantum Information Science",
            "Scientific Computation and Data Sciences",
            "Textile Conservation and Museum Studies",
            "UTeach-Natural Sciences Secondary Teaching Option",
            "UTeach-Natural Sciences Secondary Teaching Option Accelerated Track"
        ]),
        ("School of Social Work", [
            "Public Safety"
        ])
    ]
    
    var body: some View {
        if let school = selectedSchool {
            // Show certificates for selected school
            CertificateListView(
                schoolName: school,
                certificates: schools.first(where: { $0.name == school })?.certificates ?? [],
                selectedCertificate: $selectedCertificate,
                onBack: { selectedSchool = nil }
            )
        } else {
            // Show list of schools
            List {
                // None option at the top
                Button {
                    selectedCertificate = ""
                    dismiss()
                } label: {
                    HStack {
                        Text("None")
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedCertificate.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                }
                .buttonStyle(.plain)

                // School list
                ForEach(schools, id: \.name) { school in
                    Button {
                        selectedSchool = school.name
                    } label: {
                        HStack {
                            Text(school.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Certificate")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CertificateListView: View {
    let schoolName: String
    let certificates: [String]
    @Binding var selectedCertificate: String
    let onBack: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(certificates, id: \.self) { certificate in
                Button {
                    selectedCertificate = certificate
                    dismiss()
                } label: {
                    HStack {
                        Text(certificate)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedCertificate == certificate {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(schoolName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(schoolName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
    }
}

// MARK: - Tags Selection View

struct TagsSelectionView: View {
    @Binding var selectedTags: Set<String>
    @Environment(\.dismiss) private var dismiss
    
    private let availableTags = [
        "Director", "Producer", "Writer", "Actor", "Editor",
        "Composer", "Sound Mixer", "Musician", "Singer",
        "Animator", "VFX Artist", "Pixel Artist", "Game Designer",
        "Costume Designer", "Digital Designer", "Colorist"
    ]
    
    /// Maximum number of tags a user may select.
    private let maxTags = 5

    var body: some View {
        List {
            Section {
                ForEach(availableTags, id: \.self) { tag in
                    let isSelected = selectedTags.contains(tag)
                    // Once the limit is reached, only already-selected tags stay tappable.
                    let isDisabled = !isSelected && selectedTags.count >= maxTags
                    Button {
                        if isSelected {
                            selectedTags.remove(tag)
                        } else if selectedTags.count < maxTags {
                            selectedTags.insert(tag)
                        }
                    } label: {
                        HStack {
                            Text(tag)
                                .foregroundStyle(isDisabled ? .secondary : .primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .disabled(isDisabled)
                }
            } footer: {
                Text("Select up to \(maxTags) tags. (\(selectedTags.count)/\(maxTags))")
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Like Count Button

struct LikeCountButton: View {
    let submissionId: UUID
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @State private var showWhoLiked = false
    
    // Get the actual submission to access likes
    private var submission: Submission? {
        store.approvedSubmissions.first(where: { $0.id == submissionId })
    }
    
    // For now, we count from the likedSubmissionIds set
    // In a full implementation, you'd track individual users who liked
    private var likeCount: Int {
        // This is a simplified version - in production you'd have a proper likes tracking system
        store.likedSubmissionIds.contains(submissionId) ? 1 : 0
    }
    
    var body: some View {
        Button {
            showWhoLiked = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("\(likeCount) \(likeCount == 1 ? "like" : "likes")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showWhoLiked) {
            if let submission = submission {
                WhoLikedSheet(submission: submission)
            }
        }
    }
}

// MARK: - Who Liked Sheet

struct WhoLikedSheet: View {
    let submission: Submission
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    
    // Mock data for who liked - in production, track this in Submission model or CloudKit
    // For now, we'll show the current user if they liked it
    @AppStorage("userFirstName") private var userFirstName: String = ""
    @AppStorage("userLastName") private var userLastName: String = ""
    
    private var displayName: String {
        "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespaces)
    }
    
    private var usersWhoLiked: [String] {
        // In a full implementation, you'd fetch this from CloudKit or the Submission model
        // For now, show current user if they liked it
        if store.likedSubmissionIds.contains(submission.id) {
            return [displayName]
        }
        return []
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if usersWhoLiked.isEmpty {
                    ContentUnavailableView(
                        "No Likes Yet",
                        systemImage: "heart",
                        description: Text("Be the first to like this project!")
                    )
                } else {
                    List {
                        ForEach(usersWhoLiked, id: \.self) { userName in
                            HStack(spacing: 12) {
                                // Profile image placeholder
                                Circle()
                                    .fill(Color.utBrandOrange.opacity(0.3))
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .foregroundStyle(Color.utBrandOrange)
                                    }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(userName)
                                        .font(.headline)
                                    
                                    // Could add role or other info here
                                    Text("Liked this project")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Likes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Portfolio_5()
}

#Preview("Portfolio - Mock Data") {
    // Seed personal info that Portfolio_5 reads from @AppStorage (UserDefaults).
    let defaults = UserDefaults.standard
    defaults.set("Alex", forKey: "userFirstName")
    defaults.set("Rivera", forKey: "userLastName")
    defaults.set("2025", forKey: "userGraduationYear")
    defaults.set("Director, Screenwriter, Editor, Actor", forKey: "userType")
    defaults.set("Senior RTF student focused on character-driven short films and scoring. I love collaborating across departments and telling first-generation stories.", forKey: "userBio")
    defaults.set("Radio-Television-Film", forKey: "userMajor")
    defaults.set("Business", forKey: "userMinor")
    defaults.set("Digital Arts & Media", forKey: "userCertificate")
    defaults.set("Austin, TX", forKey: "userHometown")

    let name = "Alex Rivera"

    // Seed a batch of credited projects on the shared store.
    SubmissionStore_3_2.shared.approvedSubmissions = [
        Submission(
            id: UUID(), type: .film, title: "Between the Lines", details: "",
            isApproved: true, submittedBy: name,
            orderedCrew: [OrderedEntry(role: "Director", name: name),
                          OrderedEntry(role: "Editor", name: name)]
        ),
        Submission(
            id: UUID(), type: .film, title: "Last Call", details: "",
            isApproved: true, submittedBy: name,
            orderedCast: [OrderedEntry(role: "Lead", name: name)]
        ),
        Submission(
            id: UUID(), type: .film, title: "The Waiting Room", details: "",
            isApproved: true, submittedBy: name,
            orderedCrew: [OrderedEntry(role: "Screenwriter", name: name)]
        ),
        Submission(
            id: UUID(), type: .music, title: "Neon Skyline (Original Score)", details: "",
            isApproved: true, submittedBy: name,
            orderedCrew: [OrderedEntry(role: "Composer", name: name)]
        ),
        Submission(
            id: UUID(), type: .music, title: "Golden Hour", details: "",
            isApproved: true, submittedBy: name, artist: name
        ),
        Submission(
            id: UUID(), type: .reel, title: "Acting Reel 2025", details: "",
            isApproved: true, submittedBy: name
        ),
        Submission(
            id: UUID(), type: .film, title: "After the Credits", details: "",
            isApproved: true, submittedBy: name,
            orderedCrew: [OrderedEntry(role: "Director", name: name),
                          OrderedEntry(role: "Producer", name: name)]
        )
    ]

    return Portfolio_5()
}

// MARK: - User Portfolio View (read-only portfolio for another user)

/// A read-only version of the portfolio body (`Portfolio_5`) rendered for a
/// specific `UserProfile` — used when tapping a person in the Directory. It shows
/// their photo, name, class/major, role tags, bio, and the projects they are
/// credited on (as submitter, cast, or crew).
struct UserPortfolioView: View {
    let user: UserProfile
    @ObservedObject var store: SubmissionStore_3_2 = .shared

    /// Optional injected submissions for previews/testing. When provided these are
    /// used as the source (still filtered by credit) instead of the shared store.
    var previewSubmissions: [Submission]? = nil

    @State private var selectedProject: Submission?
    @State private var liked = false

    // MARK: Data

    private var sourceSubmissions: [Submission] {
        previewSubmissions ?? store.approvedSubmissions
    }

    /// Projects (excluding events and open projects) this user is credited on.
    private var creditedSubmissions: [Submission] {
        sourceSubmissions.filter { submission in
            submission.type != .event &&
            submission.type != .project &&
            isCredited(submission)
        }
    }

    private var profileImage: UIImage? {
        guard let data = user.profileImageData else { return nil }
        return UIImage(data: data)
    }

    private var academicLine: String {
        var parts: [String] = []
        // Abbreviate the graduation year to save room, e.g. "2026" → "'26".
        if !user.graduationYear.isEmpty { parts.append("Class of '\(user.graduationYear.suffix(2))") }
        if !user.major.isEmpty { parts.append(user.major) }
        return parts.joined(separator: " • ")
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileHeaderView
                bioView
                Divider()
                submissionsView
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedProject) { project in
            ProjectDetailView(post: project, liked: $liked)
        }
    }

    // MARK: View Components

    private var profileHeaderView: some View {
        HStack(spacing: 16) {
            profileImageView
            profileInfoView
        }
    }

    private var profileImageView: some View {
        Group {
            if let profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var profileInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.fullName)
                .font(.largeTitle)
                .bold()

            if !academicLine.isEmpty {
                Text(academicLine)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            if !user.tags.isEmpty {
                userTypeBubbles
            }
        }
    }

    private var userTypeBubbles: some View {
        FlowLayout(spacing: 6) {
            ForEach(user.tags, id: \.self) { role in
                Text(role)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.utBrandOrange)
                    .cornerRadius(8)
            }
        }
    }

    private var bioView: some View {
        Text(user.bio.isEmpty ? "This user hasn't added a bio yet." : user.bio)
            .foregroundStyle(user.bio.isEmpty ? .secondary : .primary)
            .italic(user.bio.isEmpty)
    }

    private var submissionsView: some View {
        Group {
            if creditedSubmissions.isEmpty {
                Text("No credited projects yet.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(creditedSubmissions) { submission in
                        submissionButton(for: submission)
                    }
                }
            }
        }
    }

    private func submissionButton(for submission: Submission) -> some View {
        Button {
            selectedProject = submission
        } label: {
            HStack(spacing: 12) {
                submissionThumbnail(for: submission)
                submissionInfo(for: submission)
                Spacer()
            }
            .padding(8)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func submissionThumbnail(for submission: Submission) -> some View {
        if let thumbnailData = submission.thumbnailData,
           let uiImage = UIImage(data: thumbnailData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 100, height: 60)
                .cornerRadius(8)
                .overlay(
                    Image(systemName: submission.type == .film ? "film" : "music.note")
                        .foregroundStyle(.secondary)
                )
        }
    }

    private func submissionInfo(for submission: Submission) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(submission.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(rolesInSubmission(submission))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: Credit Helpers

    private func isCredited(_ submission: Submission) -> Bool {
        submission.submittedBy == user.fullName ||
        submission.orderedCast.contains { $0.name == user.fullName } ||
        submission.orderedCrew.contains { $0.name == user.fullName }
    }

    /// The user's role(s) on a given submission, matching Portfolio_5's logic.
    private func rolesInSubmission(_ submission: Submission) -> String {
        if submission.orderedCast.contains(where: { $0.name == user.fullName }) {
            return "Actor"
        }
        let crewRoles = submission.orderedCrew
            .filter { $0.name == user.fullName }
            .map { $0.role }
        if !crewRoles.isEmpty {
            return crewRoles.joined(separator: ", ")
        }
        return submission.type.rawValue
    }
}

#Preview("User Portfolio") {
    // A few fake profiles with tags, majors, names, and credited projects.
    let maya = UserProfile(
        firstName: "Maya",
        lastName: "Rodriguez",
        role: "Radio-Television-Film '25",
        tags: ["Director", "Screenwriter", "Editor"],
        bio: "Senior RTF student focused on character-driven short films. Currently developing a thesis project about first-generation college students.",
        major: "Radio-Television-Film",
        graduationYear: "2025"
    )
    let jordan = UserProfile(
        firstName: "Jordan",
        lastName: "Lee",
        role: "Music '26",
        tags: ["Composer", "Producer", "Sound Design"],
        bio: "Composer and producer scoring student films and indie games.",
        major: "Music Composition",
        graduationYear: "2026"
    )
    let priya = UserProfile(
        firstName: "Priya",
        lastName: "Patel",
        role: "Theatre & Dance '24",
        tags: ["Actor", "Voice Artist"],
        bio: "Actor with a love for stage and screen. Trained in Meisner technique.",
        major: "Theatre and Dance",
        graduationYear: "2024"
    )

    let profiles = [maya, jordan, priya]

    // Fake credited projects spanning submitter, crew, and cast roles.
    let submissions: [Submission] = [
        Submission(
            id: UUID(), type: .film, title: "Between the Lines", details: "",
            isApproved: true, submittedBy: "Maya Rodriguez",
            orderedCrew: [OrderedEntry(role: "Director", name: "Maya Rodriguez"),
                          OrderedEntry(role: "Editor", name: "Maya Rodriguez")]
        ),
        Submission(
            id: UUID(), type: .film, title: "Last Call", details: "",
            isApproved: true, submittedBy: "Sam Carter",
            orderedCast: [OrderedEntry(role: "Lead", name: "Priya Patel")],
            orderedCrew: [OrderedEntry(role: "Screenwriter", name: "Maya Rodriguez")]
        ),
        Submission(
            id: UUID(), type: .music, title: "Neon Skyline (Score)", details: "",
            isApproved: true, submittedBy: "Jordan Lee",
            orderedCrew: [OrderedEntry(role: "Composer", name: "Jordan Lee")]
        ),
        Submission(
            id: UUID(), type: .film, title: "The Waiting Room", details: "",
            isApproved: true, submittedBy: "Alex Kim",
            orderedCast: [OrderedEntry(role: "Supporting", name: "Priya Patel")]
        )
    ]

    return NavigationStack {
        List(profiles) { profile in
            NavigationLink {
                UserPortfolioView(user: profile, previewSubmissions: submissions)
            } label: {
                VStack(alignment: .leading) {
                    Text(profile.fullName).font(.headline)
                    Text(profile.role).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Directory")
    }
}

// MARK: - Screen Size Previews

#if DEBUG

#Preview("Portfolio 393 × 852", traits: .fixedLayout(width: 393, height: 852)) {
    let _ = (ScreenSizeFormat.previewOverride = .size393x852)
    Portfolio_5()
}

#Preview("Portfolio 402 × 874", traits: .fixedLayout(width: 402, height: 874)) {
    let _ = (ScreenSizeFormat.previewOverride = .size402x874)
    Portfolio_5()
}

#Preview("Portfolio 430 × 932", traits: .fixedLayout(width: 430, height: 932)) {
    let _ = (ScreenSizeFormat.previewOverride = .size430x932)
    Portfolio_5()
}

#Preview("Portfolio 440 × 956", traits: .fixedLayout(width: 440, height: 956)) {
    let _ = (ScreenSizeFormat.previewOverride = .size440x956)
    Portfolio_5()
}

#endif
