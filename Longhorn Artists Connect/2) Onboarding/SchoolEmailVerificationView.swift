//
//  SchoolEmailVerificationView.swift
//  Longhorn Artists Connect
//
//  Onboarding step: confirm the user controls a school email address.
//
//  The school is derived from the email domain by the verification service, so
//  there's no school picker here — one field, one code. Callers pin the domain
//  (e.g. @my.utexas.edu for UT students) via `allowedDomains`; enthusiasts pass
//  an empty list and may use any address.
//

import SwiftUI

struct SchoolEmailVerificationView: View {
    /// Called when verification succeeds, or when the user backs out.
    let onFinished: () -> Void
    /// Label for the secondary action, or nil to hide it — onboarding requires
    /// verification to move on, so it passes nil.
    var dismissTitle: String? = "Skip for now"
    /// The school being verified. Onboarding passes the school picked a few
    /// pages earlier (it isn't saved to `userSchool` until the profile is);
    /// everywhere else falls back to the stored school.
    var school: String? = nil
    /// Domains the address must use. nil derives them from the school and the
    /// stored role; an empty list accepts any address (enthusiasts).
    var allowedDomains: [String]? = nil
    var purpose: StudentVerificationManager.Purpose = .school
    var title: String = "Verify Your School"
    var subtitle: String = "Enter your school email address. We'll send a six-digit code to confirm it's yours."

    // @Observable, so reading it in `body` is enough for invalidation — no
    // property wrapper needed for a shared instance the view doesn't own.
    private var verification: StudentVerificationManager { .shared }

    @Environment(\.colorScheme) private var colorScheme

    @State private var email: String = ""
    @State private var code: String = ""
    @State private var pending: StudentVerificationManager.PendingVerification?
    @State private var errorMessage: String?
    @State private var didSucceed = false

    /// The domain picked from `domains` when there's more than one (UT's
    /// student vs. faculty addresses on the Sign-In page).
    @State private var selectedDomain: String?

    /// The domains this address may use; empty means any address.
    private var domains: [String] {
        if let allowedDomains { return allowedDomains }
        let name = school ?? UserDefaults.standard.string(forKey: "userSchool") ?? ""
        // An empty stored school is a pre-multi-school account, which was always UT.
        guard let onboardingSchool = OnboardingSchool.named(name.isEmpty ? UserProfileModel.utSchoolName : name) else {
            return []
        }
        if let role = SchoolRole.current, let domain = onboardingSchool.domain(for: role) {
            return [domain]
        }
        return onboardingSchool.allDomains
    }

    /// The domain appended to what's typed, or nil when any address is allowed.
    private var fixedDomain: String? {
        guard let first = domains.first else { return nil }
        return selectedDomain.flatMap { domains.contains($0) ? $0 : nil } ?? first
    }

    private var idPlaceholder: String {
        OnboardingSchool.all.first { $0.allDomains.contains(fixedDomain ?? "") }?.idPlaceholder ?? "username"
    }

    /// The address the code is sent to: the typed prefix plus the fixed domain
    /// when there is one, otherwise whatever was typed.
    private var fullEmail: String {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let fixedDomain else { return trimmed }
        return trimmed.isEmpty ? "" : "\(trimmed)@\(fixedDomain)"
    }

    private var canSendCode: Bool {
        guard !verification.isBusy else { return false }
        if fixedDomain != nil {
            return !email.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".")
    }

    private var canConfirm: Bool {
        code.trimmingCharacters(in: .whitespaces).count == 6 && !verification.isBusy
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if pending == nil {
                        emailEntry
                    } else {
                        codeEntry
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
            }

            bottomActions
        }
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)

                Image(systemName: "checkmark.seal.fill")
                    .font(.title)
                    .foregroundStyle(Color.brandOrange)
            }

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }

    private var emailEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            // `axis: .vertical` keeps iOS from drawing its autofill box behind
            // single-line fields (same workaround as the other forms).
            HStack(spacing: 0) {
                TextField(fixedDomain == nil ? (purpose == .enthusiast ? "you@example.com" : "you@school.edu") : idPlaceholder,
                          text: $email, axis: .vertical)
                    .lineLimit(1)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(fixedDomain == nil ? .emailAddress : .username)
                    .onChange(of: email) { _, newValue in
                        // With a fixed domain only the part before "@" is
                        // editable — a pasted full address keeps its prefix.
                        guard fixedDomain != nil, let at = newValue.firstIndex(of: "@") else { return }
                        email = String(newValue[..<at])
                    }

                if let fixedDomain {
                    if domains.count > 1 {
                        // Sign-In doesn't know yet whether this is a student or
                        // faculty address, so let them pick the domain.
                        Menu {
                            ForEach(domains, id: \.self) { domain in
                                Button("@\(domain)") { selectedDomain = domain }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text("@\(fixedDomain)")
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .layoutPriority(1)
                    } else {
                        Text("@\(fixedDomain)")
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                }
            }
            .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colorScheme == .dark
                              ? Color.white.opacity(0.08)
                              : Color(uiColor: .secondarySystemGroupedBackground))
                )

            if purpose == .school {
                Text("Use the address your school issued you. Alumni addresses aren't eligible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("We sent a code to \(fullEmail).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("000000", text: $code, axis: .vertical)
                .lineLimit(1)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title2.monospacedDigit())
                .kerning(6)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colorScheme == .dark
                              ? Color.white.opacity(0.08)
                              : Color(uiColor: .secondarySystemGroupedBackground))
                )
                .onChange(of: code) { _, newValue in
                    // Keep it to six digits so the confirm button can't be
                    // enabled by pasted junk.
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue || digits.count > 6 {
                        code = String(digits.prefix(6))
                    }
                }

            HStack(spacing: 16) {
                Button("Use a different email") {
                    pending = nil
                    code = ""
                    errorMessage = nil
                }
                .font(.footnote)

                Button("Resend code") {
                    Task { await sendCode() }
                }
                .font(.footnote)
                .disabled(verification.isBusy)
            }
            .foregroundStyle(Color.brandOrange)
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    if pending == nil {
                        await sendCode()
                    } else {
                        await confirmCode()
                    }
                }
            } label: {
                Group {
                    if verification.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text(pending == nil ? "Send Code" : "Verify")
                    }
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background((pending == nil ? canSendCode : canConfirm) ? Color.brandOrange : Color.gray)
                .cornerRadius(12)
            }
            .disabled(pending == nil ? !canSendCode : !canConfirm)

            // Outside onboarding (Edit Profile, the reminder, the Share gate)
            // the user can back out; posting stays locked until they verify.
            if let dismissTitle {
                Button(dismissTitle) {
                    onFinished()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    // MARK: - Actions

    private func sendCode() async {
        errorMessage = nil
        do {
            pending = try await verification.requestCode(email: fullEmail, purpose: purpose)
            code = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmCode() async {
        guard let pending else { return }
        errorMessage = nil
        do {
            try await verification.confirmCode(code, for: pending)
            didSucceed = true
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SchoolEmailVerificationView(onFinished: {})
}
