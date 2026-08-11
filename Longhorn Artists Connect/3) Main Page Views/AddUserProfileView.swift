//
//  AddUserProfileView.swift
//  Longhorn Artists Connect
//
//  Moderator form for creating a local user profile from the NetworkView directory.
//  Split out of NetworkView.swift to keep that file (and its preview) lightweight.
//

import SwiftUI
import UIKit
import PhotosUI

struct AddUserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var graduationYear: String = ""
    @State private var selectedUserTypes: Set<String> = []
    @State private var bio: String = ""
    @State private var major: String = ""
    @State private var minor: String = ""
    @State private var hometown: String = ""
    @State private var profileImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showSuccessAlert = false
    
    var isFormValid: Bool {
        !firstName.isEmpty &&
        !lastName.isEmpty &&
        !graduationYear.isEmpty &&
        graduationYear.allSatisfy { $0.isNumber } &&
        graduationYear.count == 4
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Profile Photo Section
                Section {
                    VStack(spacing: 16) {
                        // Profile photo centered
                        if let profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 120))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        
                        // Photo picker
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Text("Choose Photo")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.brandOrange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        
                        if profileImage != nil {
                            Button {
                                profileImage = nil
                                selectedPhotoItem = nil
                            } label: {
                                Text("Remove Photo")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.red.opacity(0.1))
                                    .foregroundStyle(.red)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                
                // Basic Information
                Section("Basic Information") {
                    TextField("First Name", text: $firstName)
                        .autocorrectionDisabled()
                    
                    TextField("Last Name", text: $lastName)
                        .autocorrectionDisabled()
                    
                    TextField("Graduation Year", text: $graduationYear)
                        .keyboardType(.numberPad)
                    
                    ZStack(alignment: .topLeading) {
                        if bio.isEmpty {
                            Text("Tell us about this person...")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        TextEditor(text: $bio)
                            .frame(height: 100)
                    }
                }
                
                // Academic Information
                Section("Academic Information") {
                    TextField("Major", text: $major)
                        .autocorrectionDisabled()
                    
                    TextField("Minor (Optional)", text: $minor)
                        .autocorrectionDisabled()
                    
                    TextField("Hometown", text: $hometown)
                        .autocorrectionDisabled()
                }
                
                // User Type
                Section("User Type") {
                    Menu {
                        ForEach(["Director", "Producer", "Writer", "Actor", "Editor", "Composer", "Audio Engineer", "Musician", "Singer", "Animator", "VFX Artist", "Lore Writer", "Dialogue Writer", "Pixel Artist"], id: \.self) { type in
                            Button {
                                if selectedUserTypes.contains(type) {
                                    selectedUserTypes.remove(type)
                                } else {
                                    selectedUserTypes.insert(type)
                                }
                            } label: {
                                HStack {
                                    Text(type)
                                    if selectedUserTypes.contains(type) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            let summary = selectedUserTypes.isEmpty ? "Select roles" : selectedUserTypes.sorted().joined(separator: ", ")
                            Text(summary)
                                .foregroundStyle(selectedUserTypes.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add User Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createUserProfile()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isFormValid)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        profileImage = uiImage
                    }
                }
            }
        }
        .alert("Profile Created", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("\(firstName) \(lastName)'s profile has been created successfully.")
        }
    }
    
    private func createUserProfile() {
        // Create a unique key for this user profile
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        let profileKey = "userProfile_\(fullName.replacingOccurrences(of: " ", with: "_"))"
        
        // Save profile data to UserDefaults
        UserDefaults.standard.set(firstName, forKey: "\(profileKey)_firstName")
        UserDefaults.standard.set(lastName, forKey: "\(profileKey)_lastName")
        UserDefaults.standard.set(graduationYear, forKey: "\(profileKey)_graduationYear")
        UserDefaults.standard.set(selectedUserTypes.sorted().joined(separator: ", "), forKey: "\(profileKey)_userType")
        UserDefaults.standard.set(bio, forKey: "\(profileKey)_bio")
        UserDefaults.standard.set(major, forKey: "\(profileKey)_major")
        UserDefaults.standard.set(minor, forKey: "\(profileKey)_minor")
        UserDefaults.standard.set(hometown, forKey: "\(profileKey)_hometown")
        
        // Save profile image if available
        if let profileImage,
           let imageData = profileImage.jpegData(compressionQuality: 0.8) {
            UserDefaults.standard.set(imageData, forKey: "\(profileKey)_imageData")
        }
        
        // Add to list of created profiles
        var createdProfiles = UserDefaults.standard.stringArray(forKey: "createdUserProfiles") ?? []
        if !createdProfiles.contains(fullName) {
            createdProfiles.append(fullName)
            UserDefaults.standard.set(createdProfiles, forKey: "createdUserProfiles")
        }
        
        showSuccessAlert = true
    }
}
