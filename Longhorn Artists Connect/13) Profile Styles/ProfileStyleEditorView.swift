//
//  ProfileStyleEditorView.swift
//  Longhorn Artists Connect
//
//  Pick a profile style and fill in what that style's page shows: an actor's
//  headshot, reel, stats, skills and extra resume credits; a musician's artist name,
//  instruments and availability; a filmmaker's specialties and gear.
//
//  Saving keeps everything on this device immediately and uploads it to the
//  person's `CreativeProfile` record, which also puts it in the moderator's queue
//  for the public page.
//

import SwiftUI
import PhotosUI
import UIKit

struct ProfileStyleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var creative = CreativeProfileStore.shared
    @ObservedObject private var store = SubmissionStore_3_2.shared

    @AppStorage("userFirstName") private var firstName = ""
    @AppStorage("userLastName") private var lastName = ""

    @State private var style: ProfileStyle?
    @State private var details: CreativeDetails
    @State private var headshot: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var ageMinText: String
    @State private var ageMaxText: String

    init(startingStyle: ProfileStyle?) {
        let shared = CreativeProfileStore.shared
        _style = State(initialValue: startingStyle ?? shared.myStyle)
        _details = State(initialValue: shared.myDetails)
        _headshot = State(initialValue: shared.myHeadshot)
        _ageMinText = State(initialValue: shared.myDetails.actor.ageMin.map { String($0) } ?? "")
        _ageMaxText = State(initialValue: shared.myDetails.actor.ageMax.map { String($0) } ?? "")
    }

    private var myName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    /// Performance and film posts this user is on, for the reel picker.
    private var reelCandidates: [Submission] {
        let me = Collaborator.nameKey(for: myName)
        let isMe = PersonMatcher.make(name: myName, profileID: UserProfileManager.shared.getCurrentUser()?.id)
        return store.visibleApprovedSubmissions
            .filter { post in
                (post.type == .reel || post.type == .film)
                    && (Collaborator.nameKey(for: post.submittedBy) == me || !post.credits(where: isMe).isEmpty)
            }
            .sorted { $0.createdDate > $1.createdDate }
    }

    var body: some View {
        NavigationStack {
            Form {
                styleSection
                if let style {
                    switch style {
                    case .actor: actorSections
                    case .filmmaker: filmmakerSections
                    case .musician: musicianSections
                    }
                }
            }
            .navigationTitle("Profile style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(style == nil)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        headshot = image
                    }
                }
            }
        }
    }

    private func save() {
        guard let style else { return }
        var final = details
        final.actor.ageMin = Int(ageMinText.trimmingCharacters(in: .whitespaces))
        final.actor.ageMax = Int(ageMaxText.trimmingCharacters(in: .whitespaces))
        if let low = final.actor.ageMin, let high = final.actor.ageMax, low > high {
            final.actor.ageMin = high
            final.actor.ageMax = low
        }
        final.actor.resume.removeAll { $0.project.trimmingCharacters(in: .whitespaces).isEmpty }
        creative.update(style: style, details: final, headshot: headshot)
        dismiss()
    }

    // MARK: - Style

    private var styleSection: some View {
        Section {
            ForEach(ProfileStyle.allCases) { option in
                Button {
                    style = option
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.symbol)
                            .frame(width: 26)
                            .foregroundStyle(Color.brandOrange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.rawValue)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(option.pitch)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if style == option {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.brandOrange)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Base profile")
        } footer: {
            Text("Your style decides what Nexus recommends to you and how your profile looks. A moderator reviews your profile before it's listed on the public \(style?.plural ?? "Actors, Filmmakers or Musicians") page.")
        }
    }

    // MARK: - Actor

    @ViewBuilder
    private var actorSections: some View {
        Section("Headshot") {
            HStack(spacing: 16) {
                Group {
                    if let headshot {
                        Image(uiImage: headshot)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(Image(systemName: "person.crop.rectangle").foregroundStyle(.secondary))
                    }
                }
                .frame(width: 84, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text(headshot == nil ? "Choose headshot" : "Change headshot")
                    }
                    if headshot != nil {
                        Button("Remove", role: .destructive) {
                            headshot = nil
                            photoItem = nil
                        }
                    }
                }
            }
        }

        Section {
            Picker("Reel", selection: $details.actor.reelPostID) {
                Text("None").tag(String?.none)
                ForEach(reelCandidates) { post in
                    Text(post.title).tag(String?.some(post.id.uuidString))
                }
            }
        } header: {
            Text("Reel")
        } footer: {
            Text(reelCandidates.isEmpty
                 ? "Post a Performance or Film you're credited on to use it as your reel."
                 : "Pick a Performance or Film you're credited on.")
        }

        Section {
            HStack {
                Text("Playable age")
                Spacer()
                TextField("Min", text: $ageMinText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 50)
                Text("–")
                TextField("Max", text: $ageMaxText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 50)
            }
            Picker("Gender", selection: $details.actor.gender) {
                Text("Not set").tag("")
                ForEach(ActorDetails.genders, id: \.self) { Text($0).tag($0) }
            }
            TextField("Height (e.g. 5'9\")", text: $details.actor.height)
            TextField("Ethnic appearance", text: $details.actor.ethnicAppearance)
            TextField("Hair", text: $details.actor.hair)
            TextField("Eyes", text: $details.actor.eyes)
            Picker("Union", selection: $details.actor.union) {
                Text("Not set").tag("")
                ForEach(ActorDetails.unions, id: \.self) { Text($0).tag($0) }
            }
            TextField("Based in", text: $details.actor.basedIn)
        } header: {
            Text("Details")
        } footer: {
            Text("Age, gender, look and skills decide which open roles show up for you on Now.")
        }

        Section("Skills & training") {
            TextField("Special skills (e.g. guitar, stage combat)", text: $details.actor.specialSkills, axis: .vertical)
            TextField("Languages", text: $details.actor.languages, axis: .vertical)
            TextField("Training", text: $details.actor.training, axis: .vertical)
        }

        Section {
            ForEach($details.actor.resume) { $credit in
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Category", selection: $credit.category) {
                        ForEach(ResumeCredit.categories, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Project", text: $credit.project)
                    TextField("Role", text: $credit.role)
                    TextField("Director or company", text: $credit.company)
                    TextField("Year", text: $credit.year)
                        .keyboardType(.numberPad)
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                details.actor.resume.remove(atOffsets: offsets)
            }
            Button {
                details.actor.resume.append(ResumeCredit())
            } label: {
                Label("Add credit", systemImage: "plus")
            }
        } header: {
            Text("More resume credits")
        } footer: {
            Text("Roles you're credited for on Nexus are added automatically. Add plays, commercials and anything else here.")
        }
    }

    // MARK: - Filmmaker

    @ViewBuilder
    private var filmmakerSections: some View {
        Section {
            TextField("Specialties (e.g. handheld docs, color grading)", text: $details.filmmaker.specialties, axis: .vertical)
            TextField("Gear", text: $details.filmmaker.gear, axis: .vertical)
            Toggle("Open to joining crews", isOn: $details.filmmaker.openToCrew)
        } header: {
            Text("Filmmaker")
        } footer: {
            Text("Your filmography and stills come from what you're credited on. Your role tags decide which crew calls show up on Now.")
        }
    }

    // MARK: - Musician

    @ViewBuilder
    private var musicianSections: some View {
        Section {
            TextField("Artist or band name", text: $details.musician.artistName)
            TextField("Instruments", text: $details.musician.instruments)
            TextField("Genres", text: $details.musician.genres)
        } header: {
            Text("Musician")
        } footer: {
            Text("Releases posted under this artist name, or crediting you, make up your discography.")
        }

        Section("Available for") {
            Toggle("Live gigs", isOn: $details.musician.availableForGigs)
            Toggle("Session work", isOn: $details.musician.availableForSessions)
            Toggle("Scoring films", isOn: $details.musician.availableForScoring)
        }
    }
}
