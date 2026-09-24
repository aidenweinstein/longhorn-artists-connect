import SwiftUI
import PhotosUI
import CloudKit

/// Sorts portfolio submissions by a saved custom order (submission-UUID strings).
/// Posts present in `order` come first, in that exact order; anything not listed
/// (e.g. a brand-new post) falls to the end, newest first. An empty order means
/// "no custom arrangement" — plain newest-first.
func portfolioSorted(_ submissions: [Submission], order: [String]) -> [Submission] {
    guard !order.isEmpty else {
        return submissions.sorted { $0.createdDate > $1.createdDate }
    }
    let index = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    return submissions.sorted { a, b in
        switch (index[a.id.uuidString], index[b.id.uuidString]) {
        case let (x?, y?): return x < y
        case (_?, nil):    return true
        case (nil, _?):    return false
        case (nil, nil):   return a.createdDate > b.createdDate
        }
    }
}

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
    // Industry-professional profile fields (used when isIndustryProfessional is true).
    @AppStorage("isIndustryProfessional") private var isIndustryProfessional: Bool = false
    @AppStorage("userIndustry") private var userIndustry: String = ""
    @AppStorage("userCompany") private var userCompany: String = ""
    @AppStorage("userCompanyRole") private var userCompanyRole: String = ""
    @AppStorage("profileImageOffsetX") private var profileImageOffsetX: Double = 0
    @AppStorage("profileImageOffsetY") private var profileImageOffsetY: Double = 0
    @AppStorage("profileImageScale") private var profileImageScale: Double = 1.0
    @AppStorage("appearanceMode") private var appearanceMode: String = "automatic" // "light", "dark", or "automatic"
    /// The user's custom portfolio ordering as comma-separated submission UUIDs.
    /// Persisted locally for instant/offline effect and mirrored to CloudKit so other
    /// viewers see the same order.
    @AppStorage("portfolioOrder") private var portfolioOrderRaw: String = ""
    
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
    @State private var tempIndustry = ""
    @State private var tempCompany = ""
    @State private var tempCompanyRole = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var tempImageData: Data? = nil
    @State private var tempImageOffsetX: Double = 0
    @State private var tempImageOffsetY: Double = 0
    @State private var tempImageScale: Double = 1.0
    @State private var showImageAdjustment = false
    @State private var imageWasRemoved = false // Track if user explicitly removed the image
    @State private var selectedProject: Submission?
    @State private var liked = false
    @State private var showEnlargedPhoto = false

    // MARK: - Drag-to-reorder state
    /// True while the user is in "Reorder Posts" mode. Posts are only draggable in this
    /// mode; otherwise a tap just opens the post. Toggled by the Reorder/Done button.
    @State private var isReordering = false
    /// UUID string of the post currently being dragged, or nil when not reordering.
    @State private var draggingID: String?
    /// Live vertical translation of the dragged post from where the drag began.
    @State private var dragTranslation: CGFloat = 0
    /// The order snapshotted when the drag began. The list keeps rendering in THIS
    /// fixed order for the whole drag — rows only move via `.offset`, never by
    /// reordering the `ForEach` data. Mutating the array mid-drag was what interrupted
    /// the gesture (freezes) and set the implicit reflow animations fighting the finger
    /// (glitches). Nil when no drag is in progress.
    @State private var dragBaseOrder: [Submission]? = nil
    /// The slot the dragged post would drop into right now, recomputed from the finger
    /// position against the fixed base order. Drives the gap that opens under the finger.
    @State private var dragTargetIndex: Int? = nil
    /// Measured heights of each row, keyed by post UUID, used to compute slot
    /// positions for smooth, height-accurate reordering.
    @State private var rowHeights: [String: CGFloat] = [:]
    /// Safety timer that force-drops a stuck drag. On a fast flick SwiftUI sometimes
    /// never delivers the gesture's `.onEnded`, leaving the row frozen mid-drag with
    /// scrolling locked. Every movement re-arms this; if movement stops without an end
    /// event, it commits the drop to the closest slot and clears the drag state.
    @State private var reorderWatchdog: DispatchWorkItem?

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
    
    // Get user's approved submissions (excluding events and projects).
    // Uses visibleApprovedSubmissions so a post still uploading to CloudKit doesn't
    // appear here until its upload has fully confirmed.
    //
    // Shows only posts the user is actually credited on (cast, crew, or music
    // recording/production) — matching by name and by linked profile ID when a credit
    // was picked from the directory. Merely being the submitter no longer lists a post
    // here, so posts made for projects the user isn't part of stay off their profile.
    private var userSubmissions: [Submission] {
        let mine = store.visibleApprovedSubmissions.filter { submission in
            submission.type != .event &&
            submission.type != .project &&
            isSelfCredited(submission)
        }
        return portfolioSorted(mine, order: portfolioOrderIDs)
    }

    /// The current user's directory profile ID (`UserProfile_<recordName>`), used to
    /// match credits that were linked to this exact profile in the directory.
    private var currentUserProfileID: String? {
        UserProfileManager.shared.getCurrentUser()?.id
    }

    /// Whether the current user is credited on a submission — as cast, crew, or
    /// (for music) recording/production. Matches by name, and also by linked profile
    /// ID so a credit picked from the directory resolves even if the name differs.
    private func isSelfCredited(_ submission: Submission) -> Bool {
        let name = displayName
        let profileID = currentUserProfileID

        func matches(_ entry: OrderedEntry) -> Bool {
            if !name.isEmpty && entry.name == name { return true }
            if let profileID, entry.profileID == profileID { return true }
            return false
        }

        return submission.orderedCast.contains(where: matches)
            || submission.orderedCrew.contains(where: matches)
            || submission.orderedRecording.contains(where: matches)
            || submission.orderedProduction.contains(where: matches)
            // A photography post's photographer isn't in the ordered credit lists.
            || submission.isPhotographer(named: name)
    }

    /// The saved custom order as individual submission-UUID strings.
    private var portfolioOrderIDs: [String] {
        portfolioOrderRaw.split(separator: ",").map(String.init)
    }

    // MARK: - Drag-to-reorder logic

    /// The posts to display: the frozen base order while a drag is in progress (so the
    /// `ForEach` data never reorders mid-drag), otherwise the saved custom order.
    private var displayedSubmissions: [Submission] {
        dragBaseOrder ?? userSubmissions
    }

    /// Fallback row height used before a row has been measured.
    private var estimatedRowHeight: CGFloat {
        feedFormat.thumbnailWidth * 0.6 + 16
    }

    /// Measured height for a row, falling back to the estimate before it's measured.
    private func rowHeight(_ id: String) -> CGFloat {
        rowHeights[id] ?? estimatedRowHeight
    }

    /// The top Y (in the list's own coordinate space) of the slot at `position`,
    /// summing measured row heights and the inter-row spacing above it.
    private func slotTop(_ position: Int, order: [Submission]) -> CGFloat {
        var top: CGFloat = 0
        for i in 0..<max(0, min(position, order.count)) {
            top += rowHeight(order[i].id.uuidString) + feedFormat.rowSpacing
        }
        return top
    }

    /// The vertical offset for the row at `index` in the fixed base order.
    ///
    /// The dragged row follows the finger directly. Every row between its origin and the
    /// current drop target shifts by exactly one dragged-row slot (its height + spacing)
    /// to open a gap under the finger. Because the underlying `ForEach` order never
    /// changes during the drag, these are the *only* movements — no data reshuffling, so
    /// the gesture is never interrupted and the reflow can't fight the finger.
    private func rowOffset(for submission: Submission, at index: Int) -> CGFloat {
        guard let draggingID,
              let base = dragBaseOrder,
              let from = base.firstIndex(where: { $0.id.uuidString == draggingID }),
              let target = dragTargetIndex else { return 0 }

        if submission.id.uuidString == draggingID {
            return dragTranslation
        }

        let unit = rowHeight(draggingID) + feedFormat.rowSpacing
        if from < target, index > from, index <= target { return -unit }
        if from > target, index >= target, index < from { return unit }
        return 0
    }

    /// The drop slot the dragged row currently lands in, computed from the finger
    /// position against the *fixed* base layout. Recomputing absolutely each frame
    /// (rather than swapping incrementally) keeps the target stable and can't oscillate.
    private func computeTarget(translation: CGFloat, base: [Submission], from: Int) -> Int {
        let draggedID = base[from].id.uuidString
        let draggedCenter = slotTop(from, order: base) + translation + rowHeight(draggedID) / 2

        var target = from
        // Walk down while the dragged center sits below the next row's midpoint.
        while target < base.count - 1 {
            let next = target + 1
            let mid = slotTop(next, order: base) + rowHeight(base[next].id.uuidString) / 2
            if draggedCenter > mid { target = next } else { break }
        }
        // Walk up while it sits above the previous row's midpoint.
        while target > 0 {
            let prev = target - 1
            let mid = slotTop(prev, order: base) + rowHeight(base[prev].id.uuidString) / 2
            if draggedCenter < mid { target = prev } else { break }
        }
        return target
    }

    /// Begins a reorder drag for `submission`, freezing the current order as the base.
    private func beginReorder(_ submission: Submission) {
        let snapshot = userSubmissions
        guard let index = snapshot.firstIndex(where: { $0.id == submission.id }) else { return }
        draggingID = submission.id.uuidString
        dragBaseOrder = snapshot
        dragTargetIndex = index
        dragTranslation = 0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        armReorderWatchdog()
    }

    /// Updates the finger translation and recomputes the drop target as the finger moves.
    private func updateReorder(_ translation: CGFloat, for submission: Submission) {
        guard let draggingID,
              submission.id.uuidString == draggingID,
              let base = dragBaseOrder,
              let from = base.firstIndex(where: { $0.id.uuidString == draggingID }) else { return }
        dragTranslation = translation
        dragTargetIndex = computeTarget(translation: translation, base: base, from: from)
        armReorderWatchdog()
    }

    /// (Re)starts the stuck-drag safety timer. While the finger keeps moving this is
    /// pushed back on every update, so it only fires once movement stops without an end
    /// event — at which point the drop is committed to the current (closest) slot.
    private func armReorderWatchdog() {
        reorderWatchdog?.cancel()
        let work = DispatchWorkItem {
            if draggingID != nil {
                withAnimation(.easeInOut(duration: 0.2)) { endReorder() }
            }
        }
        reorderWatchdog = work
        // Long enough that continuous dragging never trips it, short enough that a
        // stuck row frees itself almost immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Commits the reordered posts (locally + to CloudKit) and clears drag state.
    private func endReorder() {
        reorderWatchdog?.cancel()
        reorderWatchdog = nil
        if let base = dragBaseOrder,
           let draggingID,
           let from = base.firstIndex(where: { $0.id.uuidString == draggingID }),
           let target = dragTargetIndex {
            var newOrder = base
            let item = newOrder.remove(at: from)
            newOrder.insert(item, at: target)
            savePortfolioOrder(newOrder.map { $0.id.uuidString })
        }
        draggingID = nil
        dragBaseOrder = nil
        dragTargetIndex = nil
        dragTranslation = 0
    }

    /// A long-press-then-drag gesture that lifts a post and reorders the list live.
    private func reorderGesture(for submission: Submission) -> some Gesture {
        // Measure the drag in the GLOBAL coordinate space, not the row's local one: the
        // dragged row is offset by its own translation, so a local-space drag would move
        // the very coordinate system it's measured in — a feedback loop that made fast
        // drags jump and stick. Global space never moves, so translation stays accurate.
        // `minimumDistance: 0` lets the drag engage instantly after the long press so a
        // quick flick isn't dropped.
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    if draggingID == nil { beginReorder(submission) }
                case .second(true, let drag):
                    if draggingID == nil { beginReorder(submission) }
                    if let drag { updateReorder(drag.translation.height, for: submission) }
                default:
                    break
                }
            }
            .onEnded { _ in
                endReorder()
            }
    }

    /// Persists the portfolio order locally and mirrors it to CloudKit so other
    /// viewers see the same arrangement.
    private func savePortfolioOrder(_ ids: [String]) {
        portfolioOrderRaw = ids.joined(separator: ",")
        Task { await savePortfolioOrderToCloudKit(ids) }
    }

    /// Writes just the portfolio ordering to the user's CloudKit profile. Fetches the
    /// existing record and updates only the `portfolioOrder` field, so it reliably
    /// persists (and reaches other viewers) without clobbering the rest of the profile —
    /// the previous full-profile blind-write was what left reorders saved only locally.
    private func savePortfolioOrderToCloudKit(_ ids: [String]) async {
        guard CloudKitManager.shared.isAvailable,
              let userRecordID = CloudKitManager.shared.userRecordID else {
            print("⚠️ CloudKit unavailable — portfolio order saved locally only")
            return
        }

        let recordID = CKRecord.ID(recordName: "UserProfile_\(userRecordID.recordName)")
        let database = CKContainer.default().publicCloudDatabase

        do {
            // Fetch-then-update so we keep the record's change tag and every other field.
            // Fall back to a fresh record if the profile doesn't exist yet.
            let record = (try? await database.record(for: recordID))
                ?? CKRecord(recordType: "UserProfile", recordID: recordID)
            record["portfolioOrder"] = ids as CKRecordValue
            try await CloudKitManager.shared.save(record: record)

            // Keep the directory cache in sync so other views reflect the new order now.
            UserProfileManager.shared.updateCachedPortfolioOrder(ids, for: recordID.recordName)
            print("✅ Portfolio order saved to CloudKit (\(ids.count) posts)")
        } catch {
            print("❌ Failed to save portfolio order to CloudKit: \(error.localizedDescription)")
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
        // List every role the user played across cast and crew, so someone who both
        // acted and (e.g.) directed reads "Actor, Director" instead of just one.
        var roles: [String] = []
        if submission.orderedCast.contains(where: { $0.name == displayName }) {
            roles.append("Actor")
        }
        for crewEntry in submission.orderedCrew where crewEntry.name == displayName {
            roles.append(crewEntry.role)
        }

        if submission.isPhotographer(named: displayName) {
            roles.append("Photographer")
        }

        if !roles.isEmpty {
            return roles.joined(separator: ", ")
        }

        // Uncredited on their own post: show "Creator" rather than the media type.
        return "Creator"
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
                if isGuestUser {
                    // Guests have no profile or feed — show an informational splash instead.
                    guestPortfolioView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: feedFormat.sectionSpacing) {
                            profileHeaderView
                            bioView
                            postsSeparator
                            submissionsView
                        }
                        // ====== UI CONTROLS!!!!! ======
                        .padding(feedFormat.contentPadding)
                        // ==============================
                    }
                    // Freeze scrolling while a post is being dragged so the reorder
                    // drag isn't stolen by the scroll pan.
                    .scrollDisabled(draggingID != nil)
                    .refreshable {
                        await refreshPortfolio()
                    }
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
                MoreView(
                    appearanceMode: $appearanceMode,
                    isModeratorMode: $isModeratorMode
                )
            }
            .fullScreenCover(isPresented: $showEnlargedPhoto) {
                if let profileImage {
                    ProfilePhotoViewer(image: profileImage)
                }
            }
            .onAppear {
                applyAppearanceMode()
            }
        }
    }
    
    // MARK: - View Components

    /// Shown to guest accounts in place of the profile/feed: a large "Guest User"
    /// title and a short description of what Nexus is.
    private var guestPortfolioView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Guest User")
                    .font(.system(size: 44, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Nexus is the social hub for creators at UT Austin. Students can share films, music, and talent reels in a closed, public feed. These posts can then be shared in a messaging private messaging network. And fostering real world connection, people can also advertise projects, opportunities, organizations, and events.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Created by Longhorn Artists Connect.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.top, 60)
            .frame(maxWidth: .infinity)
        }
    }

    private var profileHeaderView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                profileImageView
                    // Tap the photo to see it enlarged and centered (only when set).
                    .onTapGesture {
                        if profileImage != nil { showEnlargedPhoto = true }
                    }
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
        let parts: [String]
        if isIndustryProfessional {
            // Industry pros show Company Role • Company • Industry instead of academics.
            parts = [userCompanyRole, userCompany, userIndustry].filter { !$0.isEmpty }
        } else {
            // Abbreviate the graduation year to save room, e.g. "2026" → "'26".
            let shortYear = displayGraduationYear.isEmpty ? "" : "'\(displayGraduationYear.suffix(2))"
            parts = [
                shortYear.isEmpty ? "" : "Class of \(shortYear)",
                userMajor
            ].filter { !$0.isEmpty }
        }
        // Keep the info on a single line, shrinking the text before it wraps.
        return Text(parts.joined(separator: " • "))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
    
    private var userTypeBubbles: some View {
        RoleTagFlowLayout(spacing: 6) {
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

    /// Separator line between the bio and the posts, with the Reorder toggle sitting
    /// inline on its trailing edge (the line fills the remaining width to its left).
    /// Tapping enters reorder mode (posts become draggable); "Done" locks the order in.
    private var postsSeparator: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(height: 1)

            if !userSubmissions.isEmpty {
                Button {
                    if isReordering, draggingID != nil { endReorder() }
                    withAnimation(.easeInOut(duration: 0.2)) { isReordering.toggle() }
                } label: {
                    Text(isReordering ? "Done" : "Reorder Posts")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.brandOrange)
                        .fixedSize()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var submissionsView: some View {
        Group {
            if userSubmissions.isEmpty {
                Text(isGuestUser ? "Guest account. Enjoy exploring the Nexus!" : "No projects yet. Create something amazing!")
                    .foregroundStyle(.secondary)
            } else {
                let display = displayedSubmissions
                VStack(spacing: feedFormat.rowSpacing) {
                    ForEach(Array(display.enumerated()), id: \.element.id) { index, submission in
                        let isDragging = submission.id.uuidString == draggingID
                        submissionButton(for: submission)
                            // Measure each row so slot positions are height-accurate.
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: RowHeightPreferenceKey.self,
                                        value: [submission.id.uuidString: geo.size.height]
                                    )
                                }
                            )
                            // Lift the dragged row and let it follow the finger while
                            // the rest of the list opens a gap around it in real time.
                            .scaleEffect(isDragging ? 1.03 : 1)
                            .shadow(color: .black.opacity(isDragging ? 0.2 : 0),
                                    radius: isDragging ? 8 : 0, y: isDragging ? 4 : 0)
                            .offset(y: rowOffset(for: submission, at: index))
                            .zIndex(isDragging ? 1 : 0)
                            // Non-dragged rows animate as the gap opens/closes; the dragged
                            // row snaps instantly so it stays pinned under the finger.
                            .animation(isDragging ? nil : .snappy, value: dragTargetIndex)
                            .animation(.easeInOut(duration: 0.2), value: draggingID)
                            // The long-press-to-reorder gesture lives inside
                            // `submissionButton`, scoped to the thumbnail/info area so
                            // the heart like control keeps its own taps.
                    }
                }
                .onPreferenceChange(RowHeightPreferenceKey.self) { rowHeights = $0 }
            }
        }
    }
    
    private func submissionButton(for submission: Submission) -> some View {
        HStack(spacing: 12) {
            // Tapping this area opens the project; long-press-then-drag reorders it.
            // The reorder gesture lives here (not on the whole row) so it never covers
            // the like control to its right — that control keeps its own taps.
            Button {
                selectedProject = submission
            } label: {
                HStack(spacing: 12) {
                    submissionThumbnail(for: submission)
                    submissionInfo(for: submission)
                    Spacer(minLength: 0)
                }
                // Make the whole area (including the trailing space) tappable/draggable.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Reordering is confined to the central half of the screen. A touch that
            // begins within a quarter of the screen width of either edge can't lift the
            // post — it falls straight through to the ScrollView so those edge strips
            // always scroll. Only a clear band covering the middle 50% carries the
            // long-press-to-lift gesture; a quick tap on that band still opens the
            // project, and edge taps are handled by the Button beneath it.
            // The drag-to-reorder band only exists in reorder mode. Outside it, posts
            // aren't draggable — the Button above simply opens the post on tap.
            .overlay {
                if isReordering {
                    GeometryReader { geo in
                        let screenWidth = UIScreen.main.bounds.width
                        let edgeInset = screenWidth / 4          // scroll-only strip at each edge
                        let rowMinX = geo.frame(in: .global).minX
                        // Middle band, converted from screen X into this row's local X.
                        let bandMinX = max(0, edgeInset - rowMinX)
                        let bandMaxX = min(geo.size.width, screenWidth - edgeInset - rowMinX)
                        let bandWidth = max(0, bandMaxX - bandMinX)
                        Color.clear
                            .frame(width: bandWidth, height: geo.size.height)
                            .contentShape(Rectangle())
                            // Long-press-then-drag lifts and reorders the post; the
                            // high-priority gesture wins over the enclosing ScrollView's pan.
                            .highPriorityGesture(reorderGesture(for: submission))
                            .offset(x: bandMinX)
                    }
                }
            }

            // Heart + like count pinned to the right edge; taps open the likes list.
            // Only visible to collaborators credited on the post. Kept as a sibling
            // outside the reorder gesture above so tapping it always takes priority.
            PortfolioLikeControl(submissionId: submission.id, isCredited: isSelfCredited(submission))
        }
        .padding(8)
        // ====== UI CONTROLS!!!!! ======
        // Adaptive card background + a visible border. In dark mode the card is
        // lighter than the black page, so its edge reads as a border; in light mode
        // the card matches the page, so we add an explicit separator-colored stroke
        // to keep the border visible there too.
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(UIColor.separator), lineWidth: 1)
        )
        // ==============================
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

        /// Returns a copy with every size (logo, both pills, fonts, bar height, pill
        /// length) multiplied by `k`. Positions/offsets are left unchanged.
        func scaled(by k: CGFloat) -> ToolbarFormat {
            guard k != 1 else { return self }
            var f = self
            f.editWidth *= k
            f.editFontSize *= k
            f.settingsWidth *= k
            f.settingsFontSize *= k
            f.pillHeight *= k
            f.logoHeight *= k
            f.barHeight *= k
            if let p = f.pillLength { f.pillLength = p * k }
            return f
        }
    }

    /// Universal toolbar resizer: one knob that scales every toolbar element (logo, pills,
    /// fonts, bar height) across ALL screen sizes at once, keeping the per-device
    /// proportions tuned below. 1.0 = current size; 1.2 = 20% larger; 0.85 = 15% smaller.
    /// Positions and offsets are untouched.
    private var toolbarSizeMultiplier: CGFloat { 1.0 }

    // MARK: - Per-Element Toolbar Tuning (affects every screen size at once)
    // Portfolio asset (the wordmark logo).
    private var portfolioSize: CGFloat { 1.0 }      // size multiplier
    private var portfolioOffsetX: CGFloat { -3 }     // + = right
    private var portfolioOffsetY: CGFloat { 0 }     // + = down
    // Edit Profile & More buttons (moved/sized together).
    private var editMoreSize: CGFloat { 1.1 }
    private var editMoreOffsetX: CGFloat { 0 }
    private var editMoreOffsetY: CGFloat { -4 }
    private var editMorePadding: CGFloat { 0 }    // space reserved around each

    /// The per-device format, universally scaled by `toolbarSizeMultiplier`, with the
    /// Portfolio asset additionally scaled by `portfolioSize`.
    private var toolbarFormat: ToolbarFormat {
        var f = baseToolbarFormat.scaled(by: toolbarSizeMultiplier)
        f.logoHeight *= portfolioSize
        return f
    }

    /// Adjust the values in each case to tune the toolbar for that screen size.
    private var baseToolbarFormat: ToolbarFormat {
        switch ScreenSizeFormat.current {
        case .size393x852: // iPhone 14 Pro, 15, 15 Pro, 16
            return ToolbarFormat(editWidth: 45, editFontSize: 14, settingsWidth: 43, settingsFontSize: 18, pillHeight: 40, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 29, barHeight: 50)
        case .size402x874: // iPhone 16 Pro, 17
            return ToolbarFormat(editWidth: 46, editFontSize: 14, settingsWidth: 44, settingsFontSize: 18, pillHeight: 41, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 30, barHeight: 50)
        case .size430x932: // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
            return ToolbarFormat(editWidth: 49, editFontSize: 15, settingsWidth: 47, settingsFontSize: 20, pillHeight: 44, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 32, barHeight: 52)
        case .size440x956: // iPhone 16 Pro Max, 17 Pro Max
            return ToolbarFormat(editWidth: 50, editFontSize: 16, settingsWidth: 48, settingsFontSize: 20, pillHeight: 45, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 32, barHeight: 53)
        case .iPad11: // iPad Pro 11", iPad Air 11"
            return ToolbarFormat(editWidth: 64, editFontSize: 20, settingsWidth: 62, settingsFontSize: 26, pillHeight: 56, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 42, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 66)
        case .iPad13: // iPad Pro 13", iPad Air 13"
            return ToolbarFormat(editWidth: 74, editFontSize: 23, settingsWidth: 72, settingsFontSize: 30, pillHeight: 64, pillOffsetX: -4, pillOffsetY: 0, logoHeight: 49, logoOffsetX: 0, logoOffsetY: 0, pillLength: nil, barHeight: 72)
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
        HStack(spacing: 0) {
            Image("Portfolio")
                .resizable()
                .scaledToFill()
                .frame(height: toolbarFormat.logoHeight)
                .offset(x: toolbarFormat.logoOffsetX, y: toolbarFormat.logoOffsetY)
                .offset(x: portfolioOffsetX, y: portfolioOffsetY)
            Spacer(minLength: 8)
            filterPill
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Orange fills the bar and bleeds up behind the status bar / Dynamic Island.
        .frame(maxWidth: .infinity, minHeight: toolbarFormat.barHeight, maxHeight: toolbarFormat.barHeight)
        .background(Color.brandOrange, ignoresSafeAreaEdges: .top)
    }

    // TOOLBAR PILLS (distinct buttons with space between them)
    private var filterPill: some View {
        HStack(spacing: 10) {
            Button {
                // Guests have no profile to edit — this pill logs them out instead,
                // returning to the onboarding welcome screen.
                if isGuestUser {
                    logOutToOnboarding()
                } else {
                    showingLogin = true
                }
            } label: {
                Text(isGuestUser ? "Log In" : "Edit")
                    .font(.system(size: toolbarFormat.editFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: toolbarFormat.pillLength ?? toolbarFormat.editWidth, height: toolbarFormat.pillHeight)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(Color.pillActive))
            .offset(x: toolbarFormat.pillOffsetX, y: toolbarFormat.pillOffsetY)
            .padding(editMorePadding)
            .scaleEffect(editMoreSize)
            .offset(x: editMoreOffsetX, y: editMoreOffsetY)

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
            .padding(editMorePadding)
            .scaleEffect(editMoreSize)
            .offset(x: editMoreOffsetX, y: editMoreOffsetY)
        }
    }
    
    private var editProfileSheet: some View {
        EditProfileView(
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
            tempIndustry: $tempIndustry,
            tempCompany: $tempCompany,
            tempCompanyRole: $tempCompanyRole,
            isIndustryProfessional: isIndustryProfessional,
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
                userIndustry = tempIndustry
                userCompany = tempCompany
                userCompanyRole = tempCompanyRole

                // Also save to legacy format for compatibility
                profileName = "\(tempFirstName) \(tempLastName)".trimmingCharacters(in: .whitespaces)
                graduationYear = Int(tempYear) ?? 0

                // Handle profile image. Prefer saving whatever image is currently set:
                // an image in hand always wins so an adjust/change can never fall through
                // to the "removed" branch and wipe the photo. Only clear when the user
                // explicitly removed it AND there's no image to save.
                if let newImageData = tempImageData, let original = UIImage(data: newImageData) {
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
                } else if imageWasRemoved {
                    // User explicitly removed the photo and there's nothing to save.
                    profileImageData = Data()
                    profileImageOffsetX = 0
                    profileImageOffsetY = 0
                    profileImageScale = 1.0

                    // Also remove from documents directory
                    if let imagePath = UserDefaults.standard.string(forKey: "profileImagePath") {
                        try? FileManager.default.removeItem(atPath: imagePath)
                        UserDefaults.standard.removeObject(forKey: "profileImagePath")
                    }
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
                tempIndustry = userIndustry
                tempCompany = userCompany
                tempCompanyRole = userCompanyRole
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

    /// Logs the user out (returns to the onboarding welcome screen) by clearing the
    /// completed-onboarding flag. Used by the guest "Log In" pill.
    private func logOutToOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
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
        guard CloudKitManager.shared.isAvailable else {
            print("⚠️ CloudKit not available - profile saved locally only")
            return
        }
        
        do {
            guard let userRecordID = CloudKitManager.shared.userRecordID else {
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
            // Preserve the industry-professional account type on edit. The save writes a
            // fresh record, so without these an edit would drop the industry fields and
            // flags (and the profile would fall back to a UT student in the directory).
            if isIndustryProfessional {
                record["industry"] = userIndustry as CKRecordValue
                record["company"] = userCompany as CKRecordValue
                record["companyRole"] = userCompanyRole as CKRecordValue
                record["isIndustryProfessional"] = 1 as CKRecordValue
                record["isUTStudent"] = 0 as CKRecordValue
            }
            // Custom portfolio ordering (only when set, so CloudKit can infer the list type).
            if !portfolioOrderIDs.isEmpty {
                record["portfolioOrder"] = portfolioOrderIDs as CKRecordValue
            }

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
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Row Height Preference

/// Collects the measured height of each portfolio row, keyed by post UUID, so the
/// drag-to-reorder logic can compute exact slot positions.
private struct RowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Flow Layout for Role Bubbles

/// Row-based flow layout that centers each wrapped row. Shared with
/// `PersonProfileView` so other people's profiles show role tags with the exact
/// same formatting as the user's own portfolio.
struct RoleTagFlowLayout: Layout {
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
        ZStack {
            if let school = selectedSchool {
                // Show majors for selected school. Slides in from the trailing edge
                // (and back out) for a navigation-push feel.
                MajorListView(
                    schoolName: school,
                    majors: schools.first(where: { $0.name == school })?.majors ?? [],
                    selectedMajor: $selectedMajor,
                    onBack: { selectedSchool = nil }
                )
                .transition(.move(edge: .trailing))
            } else {
                schoolListView
                    .transition(.move(edge: .leading))
            }
        }
        // Animate the school-list ⇄ specific-school swap like a push/pop.
        .animation(.easeInOut, value: selectedSchool)
    }

    /// The list of colleges/schools; tapping one drills into that school's majors.
    private var schoolListView: some View {
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Major")
        .navigationBarTitleDisplayMode(.inline)
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
                    .contentShape(Rectangle())
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
                        .foregroundStyle(.primary)
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
            .presentationDragIndicator(.hidden)
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
            .presentationDragIndicator(.hidden)
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
                        .foregroundStyle(.primary)
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
            .presentationDragIndicator(.hidden)
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
            .presentationDragIndicator(.hidden)
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
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - Tags Selection View

struct TagsSelectionView: View {
    @Binding var selectedTags: Set<String>
    @Environment(\.dismiss) private var dismiss
    
    // Drive the tag list from the same source as onboarding page three
    // (`UserType.allCases`) so the two screens always offer the exact same tags.
    private let availableTags = UserType.allCases.map { $0.rawValue }
    
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

/// Trailing like indicator for a portfolio row: a heart with the like count stacked
/// beneath it, pinned to the right edge. Tapping opens the "who liked" sheet.
struct PortfolioLikeControl: View {
    let submissionId: UUID
    /// Only collaborators credited on the post may see its like count. When false,
    /// the control renders nothing so the count stays private.
    let isCredited: Bool
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @State private var showWhoLiked = false

    private var submission: Submission? {
        store.approvedSubmissions.first(where: { $0.id == submissionId })
    }

    // Authoritative cross-user like count from CloudKit, cached on the store and
    // refreshed on appear (see `.task` below). Was previously hardcoded to a local
    // 0/1, which is why other people's likes never showed on your own posts.
    private var likeCount: Int {
        store.likeCounts[submissionId] ?? 0
    }

    var body: some View {
        if isCredited {
            content
                .task { await store.refreshLikeCount(for: submissionId) }
        }
    }

    private var content: some View {
        Button {
            showWhoLiked = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                Text("\(likeCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showWhoLiked) {
            if let submission {
                WhoLikedSheet(submission: submission)
            }
        }
    }
}

/// Full-screen, centered viewer for a profile photo so people can get a better look
/// at someone's face. Tap anywhere or the close button to dismiss.
struct ProfilePhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding()

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
                            .background(Circle().fill(.black.opacity(0.5)))
                            .contentShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Who Liked Sheet

struct WhoLikedSheet: View {
    let submission: Submission
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SubmissionStore_3_2 = .shared
    @ObservedObject private var profiles = UserProfileManager.shared

    /// The people who liked this post, resolved to directory profiles when possible.
    /// A liker whose profile isn't in the directory (or who hasn't set a name) is kept
    /// as a placeholder so the count still matches the heart count.
    @State private var likers: [Liker] = []
    @State private var isLoading = true

    /// One row in the sheet. `id` is the raw iCloud user record name (unique per liker);
    /// `profile` is the resolved directory entry, or nil if we couldn't match one.
    private struct Liker: Identifiable {
        let id: String
        let profile: DirectoryUser?
        var displayName: String { profile?.displayName ?? "Guest User" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if likers.isEmpty {
                    ContentUnavailableView(
                        "No Likes Yet",
                        systemImage: "heart",
                        description: Text("No one has liked this project yet.")
                    )
                } else {
                    List {
                        ForEach(likers) { liker in
                            HStack(spacing: 12) {
                                // Show the liker's real profile photo; fall back to an
                                // icon only when they haven't set one.
                                if let data = liker.profile?.profileImageData,
                                   let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.utBrandOrange.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                        .overlay {
                                            Image(systemName: "person.fill")
                                                .foregroundStyle(Color.utBrandOrange)
                                        }
                                }

                                Text(liker.displayName)
                                    .font(.headline)

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Likes")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(.systemBackground))
        .task { await loadLikers() }
    }

    /// Fetches the raw liker IDs from CloudKit (the separate `PostLike` records) and
    /// resolves each to a directory profile for its name and photo.
    private func loadLikers() async {
        let ids = (try? await CloudKitManager.shared.fetchLikers(postID: submission.id)) ?? []
        likers = ids.map { Liker(id: $0, profile: profiles.findUser(byID: $0)) }
        isLoading = false
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

    /// The custom post ordering this user arranged on their own portfolio (synced via
    /// their CloudKit profile). Applied so their public page shows posts in the same
    /// order they set. Empty means "no custom arrangement" — newest-first.
    var portfolioOrder: [String] = []

    @State private var selectedProject: Submission?
    @State private var liked = false

    // MARK: Data

    private var sourceSubmissions: [Submission] {
        previewSubmissions ?? store.approvedSubmissions
    }

    /// Projects (excluding events and open projects) this user is credited on,
    /// arranged in the order they set on their own portfolio.
    private var creditedSubmissions: [Submission] {
        let filtered = sourceSubmissions.filter { submission in
            submission.type != .event &&
            submission.type != .project &&
            isCredited(submission)
        }
        return portfolioSorted(filtered, order: portfolioOrder)
    }

    private var profileImage: UIImage? {
        guard let data = user.profileImageData else { return nil }
        return UIImage(data: data)
    }

    private var academicLine: String {
        // Industry pros show Company Role • Company • Industry instead of academics.
        if user.isIndustryProfessional {
            return [user.companyRole, user.company, user.industry]
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
        }
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
        .presentationDragIndicator(.hidden)
    }

    // MARK: View Components

    private var profileHeaderView: some View {
        // Match the user's own portfolio (Portfolio_5): photo + name on one row, with
        // the role tags in a full-width band BELOW them rather than beside the photo.
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                profileImageView
                profileInfoView
                Spacer(minLength: 0)
            }

            if !user.tags.isEmpty {
                userTypeBubbles
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        }
    }

    private var userTypeBubbles: some View {
        RoleTagFlowLayout(spacing: 6) {
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
        .frame(maxWidth: .infinity)
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
        submission.orderedCast.contains { $0.name == user.fullName } ||
        submission.orderedCrew.contains { $0.name == user.fullName } ||
        submission.orderedRecording.contains { $0.name == user.fullName } ||
        submission.orderedProduction.contains { $0.name == user.fullName } ||
        // A photography post's photographer isn't in the ordered credit lists.
        submission.isPhotographer(named: user.fullName)
    }

    /// The user's role(s) on a given submission, matching Portfolio_5's logic. Lists
    /// every role played across cast and crew, so someone who both acted and (e.g.)
    /// directed reads "Actor, Director" instead of just one.
    private func rolesInSubmission(_ submission: Submission) -> String {
        var roles: [String] = []
        if submission.orderedCast.contains(where: { $0.name == user.fullName }) {
            roles.append("Actor")
        }
        for crewEntry in submission.orderedCrew where crewEntry.name == user.fullName {
            roles.append(crewEntry.role)
        }
        if submission.isPhotographer(named: user.fullName) {
            roles.append("Photographer")
        }
        if !roles.isEmpty {
            return roles.joined(separator: ", ")
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

#Preview("Portfolio 440 × 956") {
    let _ = (ScreenSizeFormat.previewOverride = .size440x956)
    Portfolio_5()
        .previewDevice("iPhone 16 Pro Max")
}

#endif
