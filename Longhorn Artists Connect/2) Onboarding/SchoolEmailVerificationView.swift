//
//  SchoolEmailVerificationView.swift
//  Longhorn Artists Connect
//
//  Onboarding step: confirm the user controls a school email address.
//
//  The school is derived from the email domain by the verification service, so
//  there's no school picker here — one field, one code. Adding a school is a
//  registry row on the server, not an app release.
//

import SwiftUI

struct SchoolEmailVerificationView: View {
    /// Called when verification succeeds, or when the user backs out.
    let onFinished: () -> Void
    /// Label for the secondary action. "Skip for now" reads right during
    /// onboarding; "Cancel" is what you want when opened from Edit Profile.
    var dismissTitle: String = "Skip for now"

    // @Observable, so reading it in `body` is enough for invalidation — no
    // property wrapper needed for a shared instance the view doesn't own.
    private var verification: StudentVerificationManager { .shared }

    @Environment(\.colorScheme) private var colorScheme

    @State private var email: String = ""
    @State private var code: String = ""
    @State private var pending: StudentVerificationManager.PendingVerification?
    @State private var errorMessage: String?
    @State private var didSucceed = false

    private var canSendCode: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && !verification.isBusy
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
                Text("Verify Your School")
                    .font(.title)
                    .fontWeight(.bold)

                Image(systemName: "checkmark.seal.fill")
                    .font(.title)
                    .foregroundStyle(Color.brandOrange)
            }

            Text("Enter your school email address. We'll send a six-digit code to confirm it's yours.")
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
            TextField("you@school.edu", text: $email, axis: .vertical)
                .lineLimit(1)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colorScheme == .dark
                              ? Color.white.opacity(0.08)
                              : Color(uiColor: .secondarySystemGroupedBackground))
                )

            Text("Use the address your school issued you. Alumni addresses aren't eligible.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("We sent a code to \(email.trimmingCharacters(in: .whitespaces)).")
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

            // Skipping is allowed so an outage can't wall people out of the
            // app entirely — but posting and messaging stay locked until they
            // verify. See PostingGate.
            Button(dismissTitle) {
                onFinished()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    // MARK: - Actions

    private func sendCode() async {
        errorMessage = nil
        do {
            pending = try await verification.requestCode(
                email: email.trimmingCharacters(in: .whitespaces)
            )
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
