//
//  SharedSubmissionTypes.swift
//  Longhorn Artists Connect
//
//  Shared types used across multiple submission views
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Keyboard Dismissal

/// Resigns the current first responder, dismissing the keyboard.
@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// Installs a window-level tap recognizer that dismisses the keyboard on any tap,
/// without stealing taps from buttons or text fields (`cancelsTouchesInView = false`,
/// recognizes simultaneously). Because it ends editing on every tap, tapping a
/// navigation button also resigns the active field — so the keyboard doesn't linger
/// or reappear when returning from a pushed sub-page.
private struct DismissKeyboardOnTap: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let tap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleTap))
            tap.cancelsTouchesInView = false
            tap.delegate = context.coordinator
            window.addGestureRecognizer(tap)
            context.coordinator.tap = tap
            context.coordinator.window = window
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let tap = coordinator.tap {
            coordinator.window?.removeGestureRecognizer(tap)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var tap: UITapGestureRecognizer?
        weak var window: UIWindow?

        @objc func handleTap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

extension View {
    /// Dismisses the keyboard when the user taps anywhere (outside a text field),
    /// and when tapping controls that push a new page. Unlike an `.onTapGesture`
    /// approach, this doesn't swallow taps on buttons/fields. See `DismissKeyboardOnTap`.
    func endEditingOnTap() -> some View {
        background(DismissKeyboardOnTap())
    }
}

// MARK: - Credit Name Field

/// A text field for crediting a person that suggests matching registered users as
/// you type. Tapping a suggestion fills their exact profile name so the credit
/// links to the real person (no misspellings / faulty credits).
struct CreditNameField: View {
    let placeholder: String
    @Binding var text: String
    /// Optional binding that stores the picked person's profile record ID, so the
    /// credit links to the exact person. Defaults to a no-op for fields that don't
    /// track an ID (e.g. crew name fields).
    var profileID: Binding<String?> = .constant(nil)

    @ObservedObject private var userManager = UserProfileManager.shared
    @FocusState private var isFocused: Bool

    /// Up to 4 directory users whose name contains the typed text — unless the
    /// credit is already linked to a profile (then it's considered confirmed).
    private var suggestions: [DirectoryUser] {
        if profileID.wrappedValue != nil { return [] }
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return [] }
        if userManager.allUsers.contains(where: { $0.fullName.lowercased() == query }) { return [] }
        return Array(
            userManager.allUsers
                .filter { $0.fullName.lowercased().contains(query) }
                .sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }
                .prefix(4)
        )
    }

    /// Whether this credit is linked to a real profile (picked, or exact name match).
    private var isConfirmed: Bool {
        if profileID.wrappedValue != nil { return true }
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        return !query.isEmpty && userManager.allUsers.contains { $0.fullName.lowercased() == query }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(placeholder, text: $text, axis: .vertical)
                    .focused($isFocused)
                if isConfirmed {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.brandOrange)
                        .font(.caption)
                }
            }
            // If the user edits the text away from the linked profile's name, drop
            // the stale link so the ✓ and stored ID stay accurate.
            .onChange(of: text) { _, newValue in
                if let id = profileID.wrappedValue,
                   let linked = userManager.allUsers.first(where: { $0.id == id }),
                   linked.fullName.lowercased() != newValue.trimmingCharacters(in: .whitespaces).lowercased() {
                    profileID.wrappedValue = nil
                }
            }

            if isFocused && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { user in
                        Button {
                            text = user.fullName
                            profileID.wrappedValue = user.id
                            isFocused = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(Color.brandOrange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(user.fullName)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    if !user.rolesString.isEmpty {
                                        Text(user.rolesString)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if user.id != suggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                )
            }
        }
    }
}

// MARK: - Age Rating

enum AgeRating: String, CaseIterable, Identifiable, Codable {
    case general = "G"
    case pg = "PG"
    case pg13 = "PG-13"
    case r = "R"
    
    var id: String { rawValue }
}

// MARK: - Cast & Crew Types

struct CastEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var performer: String
    var role: String
    /// CloudKit record name of the performer's profile, when picked from the
    /// directory. `nil` for free-typed names.
    var profileID: String?

    init(id: UUID = UUID(), performer: String = "", role: String = "", profileID: String? = nil) {
        self.id = id
        self.performer = performer
        self.role = role
        self.profileID = profileID
    }
}

struct CastInfo: Codable, Equatable {
    var primaries: [CastEntry] = []
    var secondaries: [CastEntry] = []
    var extras: [CastEntry] = []
    
    // Legacy fields for backward compatibility
    var legacyPrimarys: String = ""
    var legacySecondarys: String = ""
    var legacyExtras: String = ""
    
    // New detailed cast entries (for backward compatibility)
    var detailedCast: [CastEntry] = []
    
    var summary: String {
        var lines: [String] = []
        
        // New categorized cast
        if !primaries.isEmpty {
            lines.append(contentsOf: primaries
                .filter { !$0.performer.isEmpty && !$0.role.isEmpty }
                .map { "Primary - \($0.role): \($0.performer)" })
        }
        
        if !secondaries.isEmpty {
            lines.append(contentsOf: secondaries
                .filter { !$0.performer.isEmpty && !$0.role.isEmpty }
                .map { "Secondary - \($0.role): \($0.performer)" })
        }
        
        if !extras.isEmpty {
            lines.append(contentsOf: extras
                .filter { !$0.performer.isEmpty && !$0.role.isEmpty }
                .map { "Extra - \($0.role): \($0.performer)" })
        }
        
        // Legacy fields for backward compatibility
        let pairs: [(String, String)] = [
            ("Primaries", legacyPrimarys),
            ("Secondaries", legacySecondarys),
            ("Extras", legacyExtras)
        ]
        lines.append(contentsOf: pairs
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "\($0.0): \($0.1)" })
        
        // Detailed cast for backward compatibility
        if !detailedCast.isEmpty {
            lines.append(contentsOf: detailedCast
                .filter { !$0.performer.isEmpty && !$0.role.isEmpty }
                .map { "\($0.role): \($0.performer)" })
        }
        
        return lines.joined(separator: "\n")
    }
}

struct CrewInfo: Codable, Equatable {
    var director: String = ""
    var producer: String = ""
    var writer: String = ""
    var editor: String = ""

    /// Profile record IDs for credited crew, keyed by the field name (e.g.
    /// "director", "firstAC"). Populated when a name is picked from the directory.
    var profileIDs: [String: String] = [:]

    var directorOfPhotography: String = ""
    var firstAC: String = ""
    var secondAC: String = ""
    var gaffer: String = ""
    var keyGrip: String = ""
    var grip: String = ""
    var bbe: String = ""
    
    var composer: String = ""
    var onSetMixer: String = ""
    var boomOperator: String = ""
    var sfxDesigner: String = ""
    var soundMixer: String = ""
    
    var productionDesigner: String = ""
    var wardrobe: String = ""
    var hairAndMakeup: String = ""
    var setDresser: String = ""
    var stuntCoordinator: String = ""
    var colorist: String = ""
    var productionAssistant: String = ""
    
    var summary: String {
        let pairs: [(String, String)] = [
            ("Director", director),
            ("Producer", producer),
            ("Writer", writer),
            ("Editor", editor),
            ("Director of Photography", directorOfPhotography),
            ("1st Assistant Camera", firstAC),
            ("2nd Assistant Camera", secondAC),
            ("Gaffer", gaffer),
            ("Key Grip", keyGrip),
            ("Grip", grip),
            ("BBE", bbe),
            ("Composer", composer),
            ("On-Set Mixer", onSetMixer),
            ("Boom Operator", boomOperator),
            ("SFX Designer", sfxDesigner),
            ("Sound Mixer", soundMixer),
            ("Production Designer", productionDesigner),
            ("Wardrobe", wardrobe),
            ("Hair and Makeup", hairAndMakeup),
            ("Set Dresser", setDresser),
            ("Stunt Coordinator", stuntCoordinator),
            ("Colorist", colorist),
            ("Production Assistant", productionAssistant)
        ]
        return pairs
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "\($0.0): \($0.1)" }
            .joined(separator: "\n")
    }
}

// MARK: - Cast/Crew ↔ OrderedEntry Conversion

extension CastInfo {
    /// Flattens cast (primaries, then secondaries, then extras) into ordered
    /// entries, dropping rows missing a name or role. Mirrors how the submission
    /// form builds a post's cast, so editing produces identical data.
    func toOrderedEntries() -> [OrderedEntry] {
        (primaries + secondaries + extras).compactMap { entry in
            guard !entry.performer.isEmpty && !entry.role.isEmpty else { return nil }
            return OrderedEntry(role: entry.role, name: entry.performer, profileID: entry.profileID)
        }
    }

    /// Rebuilds cast from stored ordered entries. The original primary/secondary/
    /// extra grouping isn't persisted, so everything is restored under "Primary".
    init(orderedEntries entries: [OrderedEntry]) {
        self.init()
        primaries = entries.map { CastEntry(performer: $0.name, role: $0.role, profileID: $0.profileID) }
    }
}

extension CrewInfo {
    /// (fieldKey, display role, value) for every crew field, in the canonical order
    /// used by the submission form. `fieldKey` matches `CrewInfo.profileIDs` keys.
    private var roleFields: [(fieldKey: String, role: String, value: String)] {
        [
            ("director", "Director", director),
            ("producer", "Producer", producer),
            ("writer", "Writer", writer),
            ("editor", "Editor", editor),
            ("composer", "Composer", composer),
            ("directorOfPhotography", "Director of Photography", directorOfPhotography),
            ("firstAC", "1st Assistant Camera", firstAC),
            ("secondAC", "2nd Assistant Camera", secondAC),
            ("gaffer", "Gaffer", gaffer),
            ("keyGrip", "Key Grip", keyGrip),
            ("grip", "Grip", grip),
            ("bbe", "BBE", bbe),
            ("onSetMixer", "On-Set Mixer", onSetMixer),
            ("soundMixer", "Sound Mixer", soundMixer),
            ("boomOperator", "Boom Operator", boomOperator),
            ("sfxDesigner", "SFX Designer", sfxDesigner),
            ("productionAssistant", "Production Assistant", productionAssistant),
            ("productionDesigner", "Production Designer", productionDesigner),
            ("wardrobe", "Wardrobe", wardrobe),
            ("hairAndMakeup", "Hair and Makeup", hairAndMakeup),
            ("setDresser", "Set Dresser", setDresser),
            ("colorist", "Colorist", colorist),
            ("stuntCoordinator", "Stunt Coordinator", stuntCoordinator)
        ]
    }

    /// Flattens filled crew fields into ordered entries, mirroring the submission form.
    func toOrderedEntries() -> [OrderedEntry] {
        roleFields.compactMap { fieldKey, role, name in
            guard !name.isEmpty else { return nil }
            return OrderedEntry(role: role, name: name, profileID: profileIDs[fieldKey])
        }
    }

    /// Rebuilds crew from stored ordered entries by mapping each role back to its field.
    init(orderedEntries entries: [OrderedEntry]) {
        self.init()
        for entry in entries {
            let fieldKey: String?
            switch entry.role {
            case "Director": director = entry.name; fieldKey = "director"
            case "Producer": producer = entry.name; fieldKey = "producer"
            case "Writer": writer = entry.name; fieldKey = "writer"
            case "Editor": editor = entry.name; fieldKey = "editor"
            case "Composer": composer = entry.name; fieldKey = "composer"
            case "Director of Photography": directorOfPhotography = entry.name; fieldKey = "directorOfPhotography"
            case "1st Assistant Camera": firstAC = entry.name; fieldKey = "firstAC"
            case "2nd Assistant Camera": secondAC = entry.name; fieldKey = "secondAC"
            case "Gaffer": gaffer = entry.name; fieldKey = "gaffer"
            case "Key Grip": keyGrip = entry.name; fieldKey = "keyGrip"
            case "Grip": grip = entry.name; fieldKey = "grip"
            case "BBE": bbe = entry.name; fieldKey = "bbe"
            case "On-Set Mixer": onSetMixer = entry.name; fieldKey = "onSetMixer"
            case "Sound Mixer": soundMixer = entry.name; fieldKey = "soundMixer"
            case "Boom Operator": boomOperator = entry.name; fieldKey = "boomOperator"
            case "SFX Designer": sfxDesigner = entry.name; fieldKey = "sfxDesigner"
            case "Production Assistant": productionAssistant = entry.name; fieldKey = "productionAssistant"
            case "Production Designer": productionDesigner = entry.name; fieldKey = "productionDesigner"
            case "Wardrobe": wardrobe = entry.name; fieldKey = "wardrobe"
            case "Hair and Makeup": hairAndMakeup = entry.name; fieldKey = "hairAndMakeup"
            case "Set Dresser": setDresser = entry.name; fieldKey = "setDresser"
            case "Colorist": colorist = entry.name; fieldKey = "colorist"
            case "Stunt Coordinator": stuntCoordinator = entry.name; fieldKey = "stuntCoordinator"
            default: fieldKey = nil
            }
            if let fieldKey, let pid = entry.profileID {
                profileIDs[fieldKey] = pid
            }
        }
    }
}

// MARK: - Music Types

struct MusicInstrumentalist: Codable, Equatable, Identifiable {
    let id: UUID
    var performer: String
    var instrument: String
    
    init(id: UUID = UUID(), performer: String = "", instrument: String = "") {
        self.id = id
        self.performer = performer
        self.instrument = instrument
    }
}

struct MusicProductionCredit: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    
    init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
    }
}

// MARK: - Reel Types

struct ReelExperience: Codable, Equatable, Identifiable {
    let id: UUID
    var project: String
    var month: Int
    var year: Int
    
    init(id: UUID = UUID(), project: String = "", month: Int = 1, year: Int = Calendar.current.component(.year, from: Date())) {
        self.id = id
        self.project = project
        self.month = month
        self.year = year
    }
    
    var dateString: String {
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(monthNames[month - 1]) \(year)"
    }
}

struct ReelSkill: Codable, Equatable, Identifiable {
    let id: UUID
    var skill: String
    var month: Int
    var year: Int
    
    init(id: UUID = UUID(), skill: String = "", month: Int = 1, year: Int = Calendar.current.component(.year, from: Date())) {
        self.id = id
        self.skill = skill
        self.month = month
        self.year = year
    }
    
    var dateString: String {
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(monthNames[month - 1]) \(year)"
    }
}

// MARK: - Project Types

struct ProjectDate: Codable, Equatable {
    var month: Int
    var day: Int
    var year: Int
    
    init(month: Int = 1, day: Int = 1, year: Int = Calendar.current.component(.year, from: Date())) {
        self.month = month
        self.day = day
        self.year = year
    }
    
    var dateString: String {
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(monthNames[month - 1]) \(day), \(year)"
    }
}

struct ProjectReleaseDate: Codable, Equatable {
    var month: Int
    var day: Int?
    var year: Int
    
    init(month: Int = 1, day: Int? = nil, year: Int = Calendar.current.component(.year, from: Date())) {
        self.month = month
        self.day = day
        self.year = year
    }
    
    var dateString: String {
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        if let day = day {
            return "\(monthNames[month - 1]) \(day), \(year)"
        } else {
            return "\(monthNames[month - 1]) \(year)"
        }
    }
}

// MARK: - Form Views

struct CastFormView: View {
    @Binding var cast: CastInfo

    var body: some View {
        List {
            Section("Primary Cast") {
                ForEach($cast.primaries) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Role", text: $entry.role, axis: .vertical)
                        CreditNameField(placeholder: "Performer", text: $entry.performer, profileID: $entry.profileID)
                    }
                }
                .onDelete { indexSet in
                    cast.primaries.remove(atOffsets: indexSet)
                }
                
                Button("Add Primary") {
                    cast.primaries.append(CastEntry())
                }
            }
            
            Section("Secondary Cast") {
                ForEach($cast.secondaries) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Role", text: $entry.role, axis: .vertical)
                        CreditNameField(placeholder: "Performer", text: $entry.performer, profileID: $entry.profileID)
                    }
                }
                .onDelete { indexSet in
                    cast.secondaries.remove(atOffsets: indexSet)
                }
                
                Button("Add Secondary") {
                    cast.secondaries.append(CastEntry())
                }
            }
            
            Section("Extras") {
                ForEach($cast.extras) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Role", text: $entry.role, axis: .vertical)
                        CreditNameField(placeholder: "Performer", text: $entry.performer, profileID: $entry.profileID)
                    }
                }
                .onDelete { indexSet in
                    cast.extras.remove(atOffsets: indexSet)
                }
                
                Button("Add Extra") {
                    cast.extras.append(CastEntry())
                }
            }
        }
        .navigationTitle("Cast")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CrewFormView: View {
    @Binding var crew: CrewInfo

    /// A binding into `crew.profileIDs` for the given crew field key, so a picked
    /// person's profile ID is stored alongside their name.
    private func idBinding(_ key: String) -> Binding<String?> {
        Binding(
            get: { crew.profileIDs[key] },
            set: { newValue in
                if let newValue { crew.profileIDs[key] = newValue }
                else { crew.profileIDs.removeValue(forKey: key) }
            }
        )
    }

    var body: some View {
        Form {
            Section("Production") {
                CrewCreditRow(role: "Director", text: $crew.director, profileID: idBinding("director"))
                CrewCreditRow(role: "Producer", text: $crew.producer, profileID: idBinding("producer"))
                CrewCreditRow(role: "Writer", text: $crew.writer, profileID: idBinding("writer"))
                CrewCreditRow(role: "Editor", text: $crew.editor, profileID: idBinding("editor"))
            }

            Section("Camera & Lighting") {
                CrewCreditRow(role: "Director of Photography", text: $crew.directorOfPhotography, profileID: idBinding("directorOfPhotography"))
                CrewCreditRow(role: "1st AC", text: $crew.firstAC, profileID: idBinding("firstAC"))
                CrewCreditRow(role: "2nd AC", text: $crew.secondAC, profileID: idBinding("secondAC"))
                CrewCreditRow(role: "Gaffer", text: $crew.gaffer, profileID: idBinding("gaffer"))
                CrewCreditRow(role: "Key Grip", text: $crew.keyGrip, profileID: idBinding("keyGrip"))
                CrewCreditRow(role: "Grip", text: $crew.grip, profileID: idBinding("grip"))
                CrewCreditRow(role: "BBE", text: $crew.bbe, profileID: idBinding("bbe"))
            }

            Section("Sound") {
                CrewCreditRow(role: "Composer", text: $crew.composer, profileID: idBinding("composer"))
                CrewCreditRow(role: "On-Set Mixer", text: $crew.onSetMixer, profileID: idBinding("onSetMixer"))
                CrewCreditRow(role: "Boom Operator", text: $crew.boomOperator, profileID: idBinding("boomOperator"))
                CrewCreditRow(role: "SFX Designer", text: $crew.sfxDesigner, profileID: idBinding("sfxDesigner"))
                CrewCreditRow(role: "Sound Mixer", text: $crew.soundMixer, profileID: idBinding("soundMixer"))
            }

            Section("Art Department") {
                CrewCreditRow(role: "Production Designer", text: $crew.productionDesigner, profileID: idBinding("productionDesigner"))
                CrewCreditRow(role: "Wardrobe", text: $crew.wardrobe, profileID: idBinding("wardrobe"))
                CrewCreditRow(role: "Hair and Makeup", text: $crew.hairAndMakeup, profileID: idBinding("hairAndMakeup"))
                CrewCreditRow(role: "Set Dresser", text: $crew.setDresser, profileID: idBinding("setDresser"))
            }

            Section("Other") {
                CrewCreditRow(role: "Stunt Coordinator", text: $crew.stuntCoordinator, profileID: idBinding("stuntCoordinator"))
                CrewCreditRow(role: "Colorist", text: $crew.colorist, profileID: idBinding("colorist"))
                CrewCreditRow(role: "Production Assistant", text: $crew.productionAssistant, profileID: idBinding("productionAssistant"))
            }
        }
        .navigationTitle("Crew")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A single crew credit row, styled like the Music Credits form: the role name
/// stays visible as a label above the name field, so you can always tell which
/// role you're crediting even after filling in a name.
private struct CrewCreditRow: View {
    let role: String
    @Binding var text: String
    var profileID: Binding<String?>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role)
                .font(.caption)
                .foregroundStyle(.secondary)
            CreditNameField(placeholder: "Name", text: $text, profileID: profileID)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Music Credits Form Views

struct MusicCreditsFormView: View {
    @Binding var recordingCredits: [OrderedEntry]
    @Binding var productionCredits: [OrderedEntry]

    // Default role fields shown ready to fill out when no credits exist yet.
    private let defaultRecordingRoles = ["Vocalist", "Lead Guitar", "Rhythm Guitar", "Bass Guitar", "Drums"]
    private let defaultProductionRoles = ["Producer", "Mixer", "Engineer"]

    var body: some View {
        NavigationStack {
            List {
                Section("Recording") {
                    ForEach($recordingCredits) { $entry in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Role (e.g., Lead Vocals, Guitar)", text: $entry.role)
                            CreditNameField(placeholder: "Name", text: $entry.name, profileID: $entry.profileID)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        recordingCredits.remove(atOffsets: indexSet)
                    }
                    
                    Button {
                        recordingCredits.append(OrderedEntry())
                    } label: {
                        Label("Add Recording Credit", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                
                Section("Production") {
                    ForEach($productionCredits) { $entry in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Role (e.g., Producer, Mix Engineer)", text: $entry.role)
                            CreditNameField(placeholder: "Name", text: $entry.name, profileID: $entry.profileID)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        productionCredits.remove(atOffsets: indexSet)
                    }
                    
                    Button {
                        productionCredits.append(OrderedEntry())
                    } label: {
                        Label("Add Production Credit", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.brandOrange)
                    }
                }
            }
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // Seed the standard role fields the first time the form is opened.
            if recordingCredits.isEmpty {
                recordingCredits = defaultRecordingRoles.map { OrderedEntry(role: $0) }
            }
            if productionCredits.isEmpty {
                productionCredits = defaultProductionRoles.map { OrderedEntry(role: $0) }
            }
        }
    }
}

// MARK: - Project Team Form Views

/// Cast roles still open for a project. Styled like the Film cast page (a List
/// section with an Add button), but with a single field per row: the role name.
struct ProjectCastNeededFormView: View {
    @Binding var castNeeded: [String]

    var body: some View {
        List {
            Section("Roles Needed") {
                ForEach(castNeeded.indices, id: \.self) { index in
                    TextField("Role (e.g., Lead Actor)", text: $castNeeded[index], axis: .vertical)
                }
                .onDelete { indexSet in
                    castNeeded.remove(atOffsets: indexSet)
                }

                Button("Add Available Role") {
                    castNeeded.append("")
                }
            }
        }
        .navigationTitle("Cast Needed")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Crew roles still open for a project — mirrors the Cast Needed page.
struct ProjectCrewNeededFormView: View {
    @Binding var crewNeeded: [String]

    var body: some View {
        List {
            Section("Roles Needed") {
                ForEach(crewNeeded.indices, id: \.self) { index in
                    TextField("Role (e.g., Sound Mixer)", text: $crewNeeded[index], axis: .vertical)
                }
                .onDelete { indexSet in
                    crewNeeded.remove(atOffsets: indexSet)
                }

                Button("Add Available Role") {
                    crewNeeded.append("")
                }
            }
        }
        .navigationTitle("Crew Needed")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProjectCastAssembledFormView: View {
    @Binding var castAssembled: [OrderedEntry]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($castAssembled) { $entry in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Role", text: $entry.role)
                            CreditNameField(placeholder: "Actor Name", text: $entry.name, profileID: $entry.profileID)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        castAssembled.remove(atOffsets: indexSet)
                    }
                    
                    Button {
                        castAssembled.append(OrderedEntry())
                    } label: {
                        Label("Add Cast Member", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.brandOrange)
                    }
                } header: {
                    Text("Already Assembled Cast")
                }
            }
            .navigationTitle("Cast Assembled")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ProjectCrewAssembledFormView: View {
    @Binding var crewAssembled: [OrderedEntry]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($crewAssembled) { $entry in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Role", text: $entry.role)
                            CreditNameField(placeholder: "Crew Member Name", text: $entry.name, profileID: $entry.profileID)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        crewAssembled.remove(atOffsets: indexSet)
                    }
                    
                    Button {
                        crewAssembled.append(OrderedEntry())
                    } label: {
                        Label("Add Crew Member", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.brandOrange)
                    }
                } header: {
                    Text("Already Assembled Crew")
                }
            }
            .navigationTitle("Crew Assembled")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct VideoPickerView: View {
    let completion: (Result<URL, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VideoPickerHelper(completion: { result in
            completion(result)
            dismiss()
        })
    }
}

struct DocumentPickerView: View {
    let allowedTypes: [UTType]
    let completion: (Result<URL, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        DocumentPicker(
            contentTypes: allowedTypes,
            onSelect: { url in
                completion(.success(url))
                dismiss()
            },
            onCancel: {
                completion(.failure(NSError(domain: "DocumentPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cancelled"])))
                dismiss()
            }
        )
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onSelect: (URL) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void
        let onCancel: () -> Void
        
        init(onSelect: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onSelect(url)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

// MARK: - Thumbnail Selection View

struct ThumbnailSelectionView: View {
    let videoURL: URL
    @Binding var selectedThumbnail: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    @State private var thumbnails: [UIImage] = []
    @State private var isLoading = true
    @State private var showPhotoPicker = false
    
    // ====== UI CONTROLS!!!!! ======
    private let gridSpacing: CGFloat = 10
    private let thumbnailCornerRadius: CGFloat = 8
    private let selectionBorderWidth: CGFloat = 3
    private let maxThumbnailsPerScreen = 6 // Will create this many thumbnails to fit one screen
    // ==============================
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top toolbar with camera roll button
                HStack {
                    Spacer()
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                            .font(.subheadline)
                            .foregroundStyle(Color.brandOrange)
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                
                Divider()
                
                // Stills from video - non-scrollable, evenly split
                Group {
                    if isLoading {
                        VStack {
                            Spacer()
                            ProgressView("Generating thumbnails...")
                            Spacer()
                        }
                    } else if thumbnails.isEmpty {
                        VStack {
                            Spacer()
                            ContentUnavailableView(
                                "No Thumbnails",
                                systemImage: "photo.on.rectangle.angled",
                                description: Text("Could not generate thumbnails from this video")
                            )
                            Spacer()
                        }
                    } else {
                        // ====== UI CONTROLS!!!!! ======
                        // Non-scrollable grid layout that fits exactly on screen
                        GeometryReader { geometry in
                            let columns = 2
                            let rows = 3
                            let availableWidth = geometry.size.width - (gridSpacing * CGFloat(columns + 1))
                            let availableHeight = geometry.size.height - (gridSpacing * CGFloat(rows + 1))
                            let itemWidth = availableWidth / CGFloat(columns)
                            let itemHeight = availableHeight / CGFloat(rows)
                            
                            VStack(spacing: gridSpacing) {
                                ForEach(0..<rows, id: \.self) { row in
                                    HStack(spacing: gridSpacing) {
                                        ForEach(0..<columns, id: \.self) { col in
                                            let index = row * columns + col
                                            if index < thumbnails.count {
                                                Button {
                                                    selectedThumbnail = thumbnails[index]
                                                    dismiss()
                                                } label: {
                                                    Image(uiImage: thumbnails[index])
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: itemWidth, height: itemHeight)
                                                        .clipped()
                                                        .cornerRadius(thumbnailCornerRadius)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: thumbnailCornerRadius)
                                                                .stroke(selectedThumbnail == thumbnails[index] ? Color.brandOrange : Color.clear, lineWidth: selectionBorderWidth)
                                                        )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(gridSpacing)
                        }
                        // ==============================
                    }
                }
            }
            .navigationTitle("Select Thumbnail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadThumbnails()
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPickerForThumbnail(selectedImage: $selectedThumbnail, onDismiss: {
                    if selectedThumbnail != nil {
                        dismiss()
                    }
                })
            }
        }
    }
    
    private func loadThumbnails() async {
        isLoading = true
        defer { isLoading = false }
        
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        // ====== UI CONTROLS!!!!! ======
        generator.maximumSize = CGSize(width: 400, height: 400)
        // ==============================
        
        guard let duration = try? await asset.load(.duration) else { return }
        let durationSeconds = CMTimeGetSeconds(duration)
        
        var times: [CMTime] = []
        // ====== UI CONTROLS!!!!! ======
        // Split evenly based on video time to fill one screen (6 thumbnails)
        for i in 0..<maxThumbnailsPerScreen {
            let time = CMTime(seconds: durationSeconds * Double(i) / Double(maxThumbnailsPerScreen), preferredTimescale: 600)
            times.append(time)
        }
        // ==============================
        
        var generatedThumbnails: [UIImage] = []
        
        for time in times {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                generatedThumbnails.append(UIImage(cgImage: cgImage))
            }
        }
        
        await MainActor.run {
            self.thumbnails = generatedThumbnails
        }
    }
}

// MARK: - Photo Picker for Thumbnail

struct PhotoPickerForThumbnail: View {
    @Binding var selectedImage: UIImage?
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ImagePickerController(selectedImage: $selectedImage, onDismiss: {
            dismiss()
            onDismiss()
        })
    }
}

struct ImagePickerController: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(selectedImage: $selectedImage, onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        @Binding var selectedImage: UIImage?
        let onDismiss: () -> Void
        
        init(selectedImage: Binding<UIImage?>, onDismiss: @escaping () -> Void) {
            _selectedImage = selectedImage
            self.onDismiss = onDismiss
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                selectedImage = image
            }
            onDismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDismiss()
        }
    }
}

// MARK: - Video State Views

struct VideoErrorStateView: View {
    @Binding var videoLoadError: Bool
    @Binding var showVideoPicker: Bool
    @Binding var showDocumentPicker: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text("Failed to load video")
                    .foregroundStyle(.red)
            }
            
            HStack(spacing: 12) {
                Button("Retry from Photos") {
                    videoLoadError = false
                    showVideoPicker = true
                }
                .font(.caption)
                
                Button("Retry from Files") {
                    videoLoadError = false
                    showDocumentPicker = true
                }
                .font(.caption)
            }
        }
    }
}

struct VideoSuccessStateView: View {
    let videoThumbnail: UIImage?
    @Binding var showThumbnailPicker: Bool
    @Binding var showVideoPicker: Bool
    @Binding var showDocumentPicker: Bool
    
    // ====== UI CONTROLS!!!!! ======
    private let thumbnailSize: CGFloat = 60
    private let thumbnailCornerRadius: CGFloat = 8
    private let iconSpacing: CGFloat = 12
    // ==============================
    
    var body: some View {
        HStack(spacing: iconSpacing) {
            if let thumbnail = videoThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: thumbnailCornerRadius))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: thumbnailCornerRadius)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: thumbnailSize, height: thumbnailSize)
                    Image(systemName: "video.fill")
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Video selected")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                Button {
                    showThumbnailPicker = true
                } label: {
                    Text("Change thumbnail")
                        .font(.caption)
                        .foregroundStyle(Color.brandOrange)
                }
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            
            // ====== UI CONTROLS!!!!! ======
            // Moved Photos and Files buttons to the right
            HStack(spacing: 12) {
                Button {
                    showVideoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo")
                        .labelStyle(.iconOnly)
                }
                
                Button {
                    showDocumentPicker = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
            }
            // ==============================
        }
    }
}

// MARK: - Credit Name Field Preview

#if DEBUG
private struct CreditNameFieldPreviewHost: View {
    @State private var name = ""
    @State private var profileID: String?

    var body: some View {
        Form {
            Section("Type \"Test\" to see suggestions") {
                CreditNameField(placeholder: "Performer", text: $name, profileID: $profileID)
            }
            Section("Result") {
                Text("Name: \(name.isEmpty ? "—" : name)")
                Text("Linked profile ID: \(profileID ?? "—")")
                    .foregroundStyle(profileID == nil ? .secondary : .primary)
            }
        }
    }
}

#Preview("Credit Name Field") {
    UserProfileManager.seedPreviewUsers()
    return CreditNameFieldPreviewHost()
}
#endif
