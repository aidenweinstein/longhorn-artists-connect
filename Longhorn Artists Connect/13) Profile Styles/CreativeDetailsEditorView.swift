//
//  CreativeDetailsEditorView.swift
//  Longhorn Artists Connect
//
//  The extra profile fields your tags unlock (see CreativeGroup.swift), as Form
//  sections that drop straight into Edit Profile the moment a matching tag is
//  picked (`CreativeDetailsFormSections`), plus a standalone sheet built from the
//  same sections for the Edit buttons on the Portfolio section and the Now page
//  (`CreativeDetailsEditorView`).
//
//  • Actor / Dancer tags — headshot, reel, Actors Access stats, skills, extra resume credits.
//  • Musician / Singer / Composer tags — artist name, instruments, genres, availability,
//    and links to streaming pages (Spotify first).
//  • Film tags — specialties, gear, open to crews.
//
//  Everything shown here appears on the person's profile for anyone who looks
//  (see StyledProfileSection).
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Form Sections

/// The tag-unlocked sections for a `Form`. Pass the tags being edited so the sections
/// appear and disappear live as tags are toggled. The caller owns `details` and
/// `headshot` and saves them with `CreativeProfileStore.update(details:headshot:)`
/// (run `details.normalizedForSave()` first).
struct CreativeDetailsFormSections: View {
    /// The role tags being edited, by name — the sections follow these.
    let tagNames: [String]
    @Binding var details: CreativeDetails
    @Binding var headshot: UIImage?

    @ObservedObject private var store = SubmissionStore_3_2.shared

    @AppStorage("userFirstName") private var firstName = ""
    @AppStorage("userLastName") private var lastName = ""

    @State private var photoItem: PhotosPickerItem?
    @State private var ageMinText = ""
    @State private var ageMaxText = ""

    private var myName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    /// The groups the tags put the user in, in display order.
    private var groups: [CreativeGroup] {
        CreativeGroup.ordered(CreativeGroup.groups(forTagNames: tagNames))
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
        Group {
            ForEach(groups) { group in
                switch group {
                case .actor: actorSections
                case .filmmaker: filmmakerSections
                case .musician: musicianSections
                }
            }
        }
        .onAppear {
            ageMinText = details.actor.ageMin.map { String($0) } ?? ""
            ageMaxText = details.actor.ageMax.map { String($0) } ?? ""
        }
        .onChange(of: ageMinText) { _, text in
            details.actor.ageMin = Int(text.trimmingCharacters(in: .whitespaces))
        }
        .onChange(of: ageMaxText) { _, text in
            details.actor.ageMax = Int(text.trimmingCharacters(in: .whitespaces))
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

    // MARK: Actor

    @ViewBuilder
    private var actorSections: some View {
        Section {
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
                    .buttonStyle(.borderless)
                    if headshot != nil {
                        Button("Remove", role: .destructive) {
                            headshot = nil
                            photoItem = nil
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Label("Actor · Headshot", systemImage: CreativeGroup.actor.symbol)
        } footer: {
            Text("Unlocked by your \(CreativeGroup.actor.tagList) tag. Shown on your profile and on the Actors tab of the directory.")
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
            DetailOptionPicker("Hair", selection: $details.actor.hair, options: ActorDetails.hairColors)
            DetailOptionPicker("Eyes", selection: $details.actor.eyes, options: ActorDetails.eyeColors)
            Picker("Union", selection: $details.actor.union) {
                Text("Not set").tag("")
                ForEach(ActorDetails.unions, id: \.self) { Text($0).tag($0) }
            }
            TextField("Based in", text: $details.actor.basedIn)
        } header: {
            Text("Actor · Details")
        } footer: {
            Text("Age, gender, look and skills decide which open roles show up for you on Now.")
        }

        Section("Actor · Skills & training") {
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
            .buttonStyle(.borderless)
        } header: {
            Text("Actor · More resume credits")
        } footer: {
            Text("Roles you're credited for on Nexus are added automatically. Add plays, commercials and anything else here.")
        }
    }

    // MARK: Filmmaker

    @ViewBuilder
    private var filmmakerSections: some View {
        Section {
            TextField("Specialties (e.g. handheld docs, color grading)", text: $details.filmmaker.specialties, axis: .vertical)
            TextField("Gear", text: $details.filmmaker.gear, axis: .vertical)
            Toggle("Open to joining crews", isOn: $details.filmmaker.openToCrew)
        } header: {
            Label("Filmmaker", systemImage: CreativeGroup.filmmaker.symbol)
        } footer: {
            Text("Unlocked by your film tags. Your filmography and stills come from what you're credited on; your tags decide which crew calls show up on Now.")
        }
    }

    // MARK: Musician

    @ViewBuilder
    private var musicianSections: some View {
        Section {
            ForEach(StreamingService.allCases) { service in
                HStack(spacing: 10) {
                    Image(systemName: service.symbol)
                        .frame(width: 22)
                        .foregroundStyle(Color.brandOrange)
                    TextField(service.rawValue, text: streamingBinding(service), prompt: Text(service.placeholder))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        } header: {
            Label("Musician · Streaming pages", systemImage: CreativeGroup.musician.symbol)
        } footer: {
            Text("Unlocked by your \(CreativeGroup.musician.tagList) tag. Paste the link to your Spotify page (and any others); they appear as buttons on your profile.")
        }

        Section {
            TextField("Artist or band name", text: $details.musician.artistName)
        } header: {
            Text("Musician · About")
        } footer: {
            Text("Releases posted under this artist name, or crediting you, make up your discography.")
        }

        Section {
            DetailChipPicker(options: MusicianDetails.instrumentOptions, selection: $details.musician.instruments)
        } header: {
            Text("Musician · Instruments")
        } footer: {
            Text("Everything you can play. Shown under your card on the Musicians page, where people can filter by instrument.")
        }

        Section {
            DetailChipPicker(options: MusicianDetails.genreOptions, selection: $details.musician.genres)
        } header: {
            Text("Musician · Genres")
        } footer: {
            Text("People can filter the Musicians page by genre too.")
        }

        Section("Musician · Available for") {
            Toggle("Live gigs", isOn: $details.musician.availableForGigs)
            Toggle("Session work", isOn: $details.musician.availableForSessions)
            Toggle("Scoring films", isOn: $details.musician.availableForScoring)
        }
    }

    private func streamingBinding(_ service: StreamingService) -> Binding<String> {
        Binding(
            get: { details.musician.link(for: service) },
            set: { details.musician.setLink($0, for: service) }
        )
    }
}

// MARK: - Field Controls

/// A Form picker for a single detail (hair, eyes) with a fixed list of choices plus
/// "Not set". A value typed before the list existed is kept as an extra choice so
/// opening the editor never silently blanks it.
struct DetailOptionPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    init(_ title: String, selection: Binding<String>, options: [String]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    private var choices: [String] {
        let current = selection.trimmingCharacters(in: .whitespaces)
        if current.isEmpty || options.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            return options
        }
        return options + [current]
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Not set").tag("")
            ForEach(choices, id: \.self) { option in
                // Tag with the stored spelling so a legacy value still reads as selected.
                Text(option).tag(option.caseInsensitiveCompare(selection) == .orderedSame ? selection : option)
            }
        }
    }
}

/// Tappable chips for a multi-choice detail (instruments, genres), stored as one
/// comma-separated string. Anything already in the string that isn't a listed option
/// (typed in an older build) shows as its own selected chip, so nothing is lost.
struct DetailChipPicker: View {
    let options: [String]
    @Binding var selection: String

    private var selected: [String] { MusicianDetails.splitList(selection) }

    private var chips: [String] {
        let extras = selected.filter { value in
            !options.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
        }
        return options + extras
    }

    private func isOn(_ chip: String) -> Bool {
        selected.contains { $0.caseInsensitiveCompare(chip) == .orderedSame }
    }

    private func toggle(_ chip: String) {
        var values = selected
        if let index = values.firstIndex(where: { $0.caseInsensitiveCompare(chip) == .orderedSame }) {
            values.remove(at: index)
        } else {
            values.append(chip)
        }
        selection = values.joined(separator: ", ")
    }

    var body: some View {
        ProfileStyleFlowLayout(spacing: 6) {
            ForEach(chips, id: \.self) { chip in
                Button {
                    toggle(chip)
                } label: {
                    Text(chip)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isOn(chip) ? Color.brandOrange : Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(isOn(chip) ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn(chip) ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

extension CreativeDetails {
    /// Tidies what the form produced before saving: a flipped age range is swapped
    /// and blank resume rows are dropped.
    func normalizedForSave() -> CreativeDetails {
        var final = self
        if let low = final.actor.ageMin, let high = final.actor.ageMax, low > high {
            final.actor.ageMin = high
            final.actor.ageMax = low
        }
        final.actor.resume.removeAll { $0.project.trimmingCharacters(in: .whitespaces).isEmpty }
        return final
    }
}

// MARK: - Standalone Sheet

/// The same sections as their own sheet, for the Edit buttons on the Portfolio's
/// tag-unlocked section and on Now. Uses the user's saved tags.
struct CreativeDetailsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var creative = CreativeProfileStore.shared

    @AppStorage("userType") private var userTypeRaw = ""

    @State private var details: CreativeDetails
    @State private var headshot: UIImage?

    init() {
        let shared = CreativeProfileStore.shared
        _details = State(initialValue: shared.myDetails)
        _headshot = State(initialValue: shared.myHeadshot)
    }

    private var tagNames: [String] {
        userTypeRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private var hasGroups: Bool {
        !CreativeGroup.groups(forTagNames: tagNames).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if !hasGroups {
                    Section {
                        Text("Add tags like Actor, Director or Musician in Edit Profile to unlock more options here.")
                            .foregroundStyle(.secondary)
                    }
                }
                CreativeDetailsFormSections(tagNames: tagNames, details: $details, headshot: $headshot)
            }
            .navigationTitle("Profile details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        creative.update(details: details.normalizedForSave(), headshot: headshot)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasGroups)
                }
            }
        }
    }
}

#Preview {
    CreativeDetailsEditorView()
}
