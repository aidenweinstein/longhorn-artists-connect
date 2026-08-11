//
//  E2) StudioModel.swift
//  Longhorn Artists Connect
//
//  Data model and manager for Studios (Collective & Incubator)
//

import SwiftUI
import PhotosUI
import Combine

// MARK: - Studio Type

enum StudioType: String, CaseIterable, Codable {
    case collective = "Collective"
    case incubator = "Incubator"

    var tagline: String {
        switch self {
        case .collective: return "A community of collaborating artists."
        case .incubator: return "A development space for emerging creators."
        }
    }

    var icon: String {
        switch self {
        case .collective: return "person.3.fill"
        case .incubator: return "lightbulb.fill"
        }
    }
}

// MARK: - Studio Model

struct Studio: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: StudioType
    var name: String
    var tagline: String
    var bio: String
    var members: [String]           // Display names
    var featuredSubmissionIDs: [UUID]
    var bannerImageData: Data?
    var logoImageData: Data?
    var instagramHandle: String
    var websiteURL: String
    var foundedYear: String

    init(
        id: UUID = UUID(),
        type: StudioType,
        name: String = "",
        tagline: String = "",
        bio: String = "",
        members: [String] = [],
        featuredSubmissionIDs: [UUID] = [],
        bannerImageData: Data? = nil,
        logoImageData: Data? = nil,
        instagramHandle: String = "",
        websiteURL: String = "",
        foundedYear: String = ""
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.tagline = tagline
        self.bio = bio
        self.members = members
        self.featuredSubmissionIDs = featuredSubmissionIDs
        self.bannerImageData = bannerImageData
        self.logoImageData = logoImageData
        self.instagramHandle = instagramHandle
        self.websiteURL = websiteURL
        self.foundedYear = foundedYear
    }
}

// MARK: - Studio Page Manager

@MainActor
class StudioPageManager: ObservableObject {

    static let shared = StudioPageManager()

    @Published var studios: [Studio] = []

    private let saveKey = "savedStudios"

    private init() {
        load()
        if studios.isEmpty {
            seedDefaults()
        }
    }

    // MARK: - Persistence

    func save() {
        if let encoded = try? JSONEncoder().encode(studios) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: saveKey),
            let decoded = try? JSONDecoder().decode([Studio].self, from: data)
        else { return }
        studios = decoded
    }

    // MARK: - Seed placeholder studios

    private func seedDefaults() {
        studios = [
            Studio(
                type: .collective,
                name: "Collective",
                tagline: StudioType.collective.tagline,
                bio: "A creative collective of UT Austin filmmakers, musicians, and artists.",
                members: [],
                foundedYear: "2024"
            ),
            Studio(
                type: .incubator,
                name: "Incubator",
                tagline: StudioType.incubator.tagline,
                bio: "A development space where emerging artists build their first projects.",
                members: [],
                foundedYear: "2024"
            )
        ]
        save()
    }

    // MARK: - CRUD

    func studio(for type: StudioType) -> Studio? {
        studios.first { $0.type == type }
    }

    func update(_ studio: Studio) {
        if let index = studios.firstIndex(where: { $0.id == studio.id }) {
            studios[index] = studio
        } else {
            studios.append(studio)
        }
        save()
    }

    func addMember(_ name: String, to type: StudioType) {
        guard var studio = studio(for: type) else { return }
        guard !studio.members.contains(name) else { return }
        studio.members.append(name)
        update(studio)
    }

    func removeMember(_ name: String, from type: StudioType) {
        guard var studio = studio(for: type) else { return }
        studio.members.removeAll { $0 == name }
        update(studio)
    }

    func pinSubmission(_ id: UUID, to type: StudioType) {
        guard var studio = studio(for: type) else { return }
        guard !studio.featuredSubmissionIDs.contains(id) else { return }
        studio.featuredSubmissionIDs.insert(id, at: 0)
        update(studio)
    }

    func unpinSubmission(_ id: UUID, from type: StudioType) {
        guard var studio = studio(for: type) else { return }
        studio.featuredSubmissionIDs.removeAll { $0 == id }
        update(studio)
    }
}
