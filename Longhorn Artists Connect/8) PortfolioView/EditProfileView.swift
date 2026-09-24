//
//  EditProfileView.swift
//  Longhorn Artists Connect
//
//  The sheet for editing the signed-in user's own profile: photo, name, year,
//  bio, major/minor/certificate and role tags.
//  Extracted from PortfolioView.swift.
//

import SwiftUI
import PhotosUI
import CloudKit

// MARK: - Edit Profile Sheet

struct EditProfileView: View {
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
    @Binding var tempIndustry: String
    @Binding var tempCompany: String
    @Binding var tempCompanyRole: String
    /// When true, the sheet shows Industry / Company / Company Role text fields in
    /// place of the Class/Academic/Tags sections.
    let isIndustryProfessional: Bool
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
    @State private var showEmailVerification = false

    private let availableYears = Array(2016...2036).map { String($0) }

    /// School email verification status, matching the academic rows' look.
    ///
    /// Verified is terminal and read-only: the authoritative flag lives in the
    /// `Verification` CloudKit record, which only the verification service can
    /// write, so there's nothing here for the user to edit or undo.
    @ViewBuilder
    private var schoolEmailRow: some View {
        if case .verified(let schoolName) = StudentVerificationManager.shared.status {
            HStack {
                Text("School Email")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Color.utBrandOrange)
                Text(schoolName.isEmpty ? "Verified" : schoolName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            Button {
                showEmailVerification = true
            } label: {
                HStack {
                    Text("School Email")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Verify")
                        .foregroundStyle(Color.utBrandOrange)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.utBrandOrange)
                }
            }
            .buttonStyle(.plain)
        }
    }

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

    /// Profile photo, with the Adjust / Change / Remove controls.
    @ViewBuilder
    private var photoSection: some View {
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
                    let hasPhoto = tempImageData != nil || (profileImage != nil && !imageWasRemoved)
                    // Adjust the existing/selected photo.
                    if hasPhoto {
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
                        // Borderless so a tap fires only this button — a plain
                        // Button in a List row makes the whole row tappable, which
                        // triggered "Remove" at the same time and wiped the photo.
                        .buttonStyle(.borderless)
                    }

                    // Pick a photo — available whether or not one already exists.
                    // Choosing a new one keeps the old photo until the new one
                    // loads, so changing a photo can never accidentally clear it.
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Text(hasPhoto ? "Change Photo" : "Choose Photo")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.utBrandOrange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    // Remove the photo entirely.
                    if hasPhoto {
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
                        .buttonStyle(.borderless)
                    } else {
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    /// Name, class year, bio, and the school email verification row.
    @ViewBuilder
    private var basicInformationSection: some View {
        // Basic Information
        Section("Basic Information") {
            // `axis: .vertical` makes this behave like the Bio field: a single-line
            // TextField gets iOS's contacts-autofill fill drawn behind the value
            // (a system color that ignores tint/textContentType), but the vertical
            // (multiline-style) field doesn't. `lineLimit(1)` keeps it one line.
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
            ), axis: .vertical)
            .lineLimit(1)
            .autocorrectionDisabled()
            .textContentType(nil)

            // Students pick a graduation year; industry pros have no class year.
            if !isIndustryProfessional {
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
            }

            TextField("Bio", text: $tempBio, axis: .vertical)
                .lineLimit(3...6)

            // School email verification. Accounts created before
            // verification existed are never forced through it, so this
            // is how they opt in. Industry pros have no school email.
            if !isIndustryProfessional, StudentVerificationManager.isUIAvailable {
                schoolEmailRow
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    /// Industry Professional fields, shown in place of the academic sections.
    @ViewBuilder
    private var professionalSection: some View {
        // Industry Professional: Industry / Company / Company Role.
        // `axis: .vertical` keeps single-line fields free of iOS's autofill fill.
        Section("Professional") {
            TextField("Industry", text: $tempIndustry, axis: .vertical)
                .lineLimit(1)
                .autocorrectionDisabled()
                .textContentType(nil)
            TextField("Company", text: $tempCompany, axis: .vertical)
                .lineLimit(1)
                .autocorrectionDisabled()
                .textContentType(nil)
            TextField("Company Role", text: $tempCompanyRole, axis: .vertical)
                .lineLimit(1)
                .autocorrectionDisabled()
                .textContentType(nil)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
    }

    /// Major / Minor / Certificate rows.
    @ViewBuilder
    private var academicSection: some View {
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
    }

    /// Tags picker row.
    @ViewBuilder
    private var tagsSection: some View {
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

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                basicInformationSection

                if isIndustryProfessional {
                    professionalSection
                } else {
                    academicSection
                    tagsSection
                }
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
                    // Industry pros have no class year, so only require a name for them.
                    .disabled(tempFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                             (!isIndustryProfessional && tempYear.isEmpty))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
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
        .sheet(isPresented: $showEmailVerification) {
            NavigationStack {
                SchoolEmailVerificationView(
                    onFinished: { showEmailVerification = false },
                    dismissTitle: "Cancel"
                )
            }
        }
        .task {
            // Refresh so a verification completed on another device shows here.
            if StudentVerificationManager.isConfigured {
                await StudentVerificationManager.shared.refreshStatus()
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
