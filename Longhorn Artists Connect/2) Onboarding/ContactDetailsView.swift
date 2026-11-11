//
//  ContactDetailsView.swift
//  Longhorn Artists Connect
//
//  A short name (and optionally phone) form used where there's no school email:
//    - Alumni give their name and phone number before the profile details.
//    - Enthusiasts give their name after verifying an email, then they're done.
//

import SwiftUI

struct ContactDetailsView: View {
    let title: String
    let subtitle: String
    /// Raw "First Last" input, owned by `OnboardingView`.
    @Binding var fullName: String
    /// nil hides the phone field.
    var phoneNumber: Binding<String>? = nil
    let buttonTitle: String
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Digits only, so formatting like "(512) 555-0100" still counts.
    private var phoneDigits: String {
        phoneNumber?.wrappedValue.filter(\.isNumber) ?? ""
    }

    private var isValid: Bool {
        let nameValid = !fullName.trimmingCharacters(in: .whitespaces).isEmpty
        let phoneValid = phoneNumber == nil || (10...15).contains(phoneDigits.count)
        return nameValid && phoneValid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 24)

            VStack(spacing: 0) {
                field(title: "First & Last Name", text: $fullName)
                    .autocorrectionDisabled()

                if let phoneNumber {
                    Divider().padding(.leading, 16)

                    field(title: "Phone Number", text: phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
            }
            // Card fill in light mode only (matches CreateProfileView).
            .background(colorScheme == .dark ? Color.clear : Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if phoneNumber != nil {
                Text("Your phone number stays private. It's never shown on your profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onContinue) {
                Text(buttonTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValid ? Color.brandOrange : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!isValid)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    /// A labeled row. `axis: .vertical` keeps iOS from drawing its autofill box
    /// behind single-line fields (same workaround as the other forms).
    private func field(title: String, text: Binding<String>) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            TextField("", text: text, axis: .vertical)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    @Previewable @State var name = ""
    @Previewable @State var phone = ""
    ContactDetailsView(
        title: "Welcome Back",
        subtitle: "Alumni don't need a school email. Tell us who you are.",
        fullName: $name,
        phoneNumber: $phone,
        buttonTitle: "Next",
        onContinue: {}
    )
}
