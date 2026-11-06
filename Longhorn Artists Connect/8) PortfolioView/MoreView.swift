//
//  MoreView.swift
//  Longhorn Artists Connect
//
//  The Portfolio tab's "More" screen (navigation title "More"): appearance mode,
//  moderator sign-in, guest state and the rest of the account settings.
//  Extracted from PortfolioView.swift.
//

import SwiftUI
import PhotosUI
import CloudKit

// MARK: - Settings View

struct MoreView: View {
    @Binding var appearanceMode: String
    @Binding var isModeratorMode: Bool
    @AppStorage("isGuestUser") private var isGuestUser: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @Namespace private var namespace
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showSavedCollections = false
    @State private var isDeletingAccount = false

    /// Whether the signed-in profile is the moderator (gates whether the Moderation
    /// section is shown at all).
    private var isModerator: Bool {
        ModeratorAccess.isModerator
    }

    /// Maps the appearance preference to a SwiftUI color scheme so the sheet re-tints
    /// instantly when Light/Dark/Auto is tapped (a window-level override doesn't reliably
    /// reach a presented sheet).
    ///
    /// Automatic resolves to the *concrete* device scheme rather than `nil`: SwiftUI
    /// won't reliably revert a presented sheet that was previously forced light/dark,
    /// so `nil` leaves the sheet stuck. In auto the window override is `.unspecified`,
    /// so the window's resolved style reflects the actual system setting.
    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:
            _ = systemColorScheme // re-evaluate when the system appearance changes
            return resolvedWindowScheme
        }
    }

    /// The window's currently resolved appearance. With the override set to
    /// `.unspecified` (automatic), this is the device's system light/dark setting.
    private var resolvedWindowScheme: ColorScheme {
        let windowScene = UIApplication.shared.connectedScenes
            .first { $0 is UIWindowScene } as? UIWindowScene
        let style = windowScene?.windows.first?.traitCollection.userInterfaceStyle ?? .light
        return style == .dark ? .dark : .light
    }

    /// Session unlock state for the moderator switch. Observed so the switch enables
    /// the instant the correct password is entered.
    @ObservedObject private var moderatorSession = ModeratorSession.shared
    @State private var moderatorPasswordInput = ""
    @State private var moderatorPasswordError = false

    /// Inbox the moderator's test verification code is sent to.
    private static let testVerificationEmail = "arw4336@my.utexas.edu"
    @State private var isSendingTestVerificationEmail = false
    /// Outcome of the last test send. Stays on screen until the next send so
    /// it can be read against the inbox at leisure.
    @State private var testVerificationEmailResult: String?
    
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
                
                // Only show moderation controls for the moderator's profile.
                if isModerator {
                    Section {
                        Toggle(isOn: $isModeratorMode) {
                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(.secondary)
                                Text("Moderator Mode")
                            }
                        }
                        // Locked until the session password is entered below.
                        .disabled(!moderatorSession.isUnlocked)

                        // Password gate. The unlock control lives on the right of the
                        // password field, showing a locked/unlocked key to indicate state.
                        HStack {
                            if moderatorSession.isUnlocked {
                                Text("Unlocked")
                                    .foregroundStyle(.secondary)
                            } else {
                                // Vertical (multiline-style) TextField, single-lined, to
                                // avoid iOS's autofill fill drawn behind a single-line
                                // field — same fix as the name field. Note: this shows the
                                // typed characters (no masking dots).
                                TextField("Password", text: $moderatorPasswordInput, axis: .vertical)
                                    .lineLimit(1)
                                    .textContentType(nil)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .submitLabel(.go)
                                    .onSubmit { attemptModeratorUnlock() }
                            }

                            Spacer(minLength: 8)

                            Button {
                                attemptModeratorUnlock()
                            } label: {
                                Image(systemName: moderatorSession.isUnlocked ? "lock.open.fill" : "lock.fill")
                                    .foregroundStyle(moderatorSession.isUnlocked ? .green : Color.utBrandOrange)
                            }
                            .buttonStyle(.borderless)
                            .disabled(moderatorSession.isUnlocked || moderatorPasswordInput.isEmpty)
                        }
                        // Match the standard grouped-row color so the field doesn't look
                        // like a differently-shaded box from the rest of the section.
                        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))

                        if moderatorPasswordError && !moderatorSession.isUnlocked {
                            Text("Incorrect password.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        // Deliverability check: emails a real verification code
                        // to the moderator's test inbox through the live service.
                        // Only once the mode is actually on, so it can't be
                        // tapped from a locked sheet.
                        if isModeratorMode {
                            Button {
                                Task { await sendTestVerificationEmail() }
                            } label: {
                                HStack {
                                    if isSendingTestVerificationEmail {
                                        ProgressView()
                                            .padding(.trailing, 4)
                                    } else {
                                        Image(systemName: "envelope.badge")
                                            .foregroundStyle(Color.utBrandOrange)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Send Test Verification Email")
                                            .foregroundStyle(.primary)
                                        Text(Self.testVerificationEmail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isSendingTestVerificationEmail)

                            if let testVerificationEmailResult {
                                Text(testVerificationEmailResult)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    } header: {
                        Text("Moderation")
                    }
                }
                
                Section {
                    if isGuestUser {
                        // Guests have no account — the only action is logging back in.
                        Button {
                            logOut()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Log In")
                            }
                        }
                    } else {
                        Button {
                            showLogoutConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundStyle(.blue)
                                Text("Log Out")
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                if isDeletingAccount {
                                    ProgressView()
                                        .padding(.trailing, 4)
                                } else {
                                    Image(systemName: "person.crop.circle.badge.xmark")
                                        .foregroundStyle(.red)
                                }
                                Text("Delete Account")
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeletingAccount)
                    }
                } header: {
                    Text("Account")
                }
            }
            .listSectionSpacing(.compact)
            // A normal account's sections fit the medium detent, so keep it fixed. Only
            // the moderator's profile adds the extra Moderation section that needs to scroll.
            .scrollDisabled(!isModerator)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(uiColor: .systemBackground)) // opaque sheet, no transparency
        // Native confirmation alerts, matching the rest of the app.
        .alert("Are you sure?", isPresented: $showLogoutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) { logOut() }
        } message: {
            Text("You will be logged out and returned to the welcome screen.")
        }
        .alert("Are you really sure?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Account", role: .destructive) { deleteAccount() }
        } message: {
            Text("This permanently removes your profile from Nexus and returns you to the welcome screen. This can't be undone.")
        }
        // Re-tint the sheet immediately when the appearance changes.
        .preferredColorScheme(preferredColorScheme)
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

    /// Sends a real verification code to the moderator's test inbox. Same
    /// endpoint, template and sender as a student would get, so what lands in
    /// the inbox is exactly what users see. The code is never confirmed, so no
    /// `Verification` record is written and the account is unchanged.
    private func sendTestVerificationEmail() async {
        isSendingTestVerificationEmail = true
        testVerificationEmailResult = nil
        defer { isSendingTestVerificationEmail = false }

        let sentAt = Date.now.formatted(date: .omitted, time: .shortened)
        do {
            let pending = try await StudentVerificationManager.shared.sendTestCode(
                email: Self.testVerificationEmail
            )
            let expires = pending.expiresAt.formatted(date: .omitted, time: .shortened)
            testVerificationEmailResult =
                "Sent at \(sentAt) for \(pending.schoolName). The code in it is valid until \(expires)."
        } catch {
            testVerificationEmailResult = "Send failed at \(sentAt): \(error.localizedDescription)"
        }
    }

    /// Validates the entered moderator password; unlocks the switch on success or
    /// flags an error on failure.
    private func attemptModeratorUnlock() {
        if moderatorSession.unlock(with: moderatorPasswordInput) {
            moderatorPasswordError = false
            moderatorPasswordInput = ""
        } else {
            moderatorPasswordError = true
        }
    }
}
