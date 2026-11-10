//
//  DirectoryFilters.swift
//  Longhorn Artists Connect
//
//  The filter menu on the directory's Actors / Filmmakers / Musicians pages. Each
//  page filters by what matters there: actors by gender, age range, height, hair and
//  eyes; filmmakers by their role on set; musicians by instrument and genre.
//  (Everyone keeps its role-tag filter, in NetworkDirectoryView.) Options come from
//  the fixed lists on ActorDetails / MusicianDetails plus anything people have typed,
//  so details saved as free text before the pickers existed still filter.
//

import Foundation

/// One filter group on a page — "Hair" and its colors.
struct DirectoryFacet: Identifiable {
    let id: String
    let title: String
    let options: [String]
}

/// A chosen option within a facet.
struct DirectoryFilterChoice: Hashable {
    let facet: String
    let option: String
}

enum DirectoryFilters {
    // Facet IDs.
    static let gender = "gender"
    static let age = "age"
    static let height = "height"
    static let hair = "hair"
    static let eyes = "eyes"
    static let role = "role"
    static let instrument = "instrument"
    static let genre = "genre"

    /// The facets for a page, with options drawn from the fixed lists plus whatever
    /// the listed people have entered.
    static func facets(for tab: DirectoryTab, people: [DirectoryUser], creative: CreativeProfileStore) -> [DirectoryFacet] {
        switch tab {
        case .everyone:
            return []
        case .actors:
            let actors = people.compactMap { creative.profile(forUserID: $0.id)?.details.actor }
            return [
                DirectoryFacet(id: gender, title: "Gender", options: ActorDetails.genders),
                DirectoryFacet(id: age, title: "Age range", options: ActorDetails.ageBands.map(\.label)),
                DirectoryFacet(id: height, title: "Height", options: ActorDetails.heightBands.map(\.label)),
                DirectoryFacet(id: hair, title: "Hair", options: merged(ActorDetails.hairColors, seen: actors.map(\.hair))),
                DirectoryFacet(id: eyes, title: "Eyes", options: merged(ActorDetails.eyeColors, seen: actors.map(\.eyes))),
            ]
        case .filmmakers:
            let roles = UserType.allCases.filter { CreativeGroup.filmmaker.tags.contains($0) }.map(\.rawValue)
            return [DirectoryFacet(id: role, title: "Role on set", options: roles)]
        case .musicians:
            let musicians = people.compactMap { creative.profile(forUserID: $0.id)?.details.musician }
            return [
                DirectoryFacet(id: instrument, title: "Instrument",
                               options: merged(MusicianDetails.instrumentOptions, seen: musicians.flatMap(\.instrumentList))),
                DirectoryFacet(id: genre, title: "Genre",
                               options: merged(MusicianDetails.genreOptions, seen: musicians.flatMap(\.genreList))),
            ]
        }
    }

    /// Whether a person passes the chosen filters: any chosen option within a facet,
    /// and every facet that has a choice.
    static func matches(_ user: DirectoryUser, tab: DirectoryTab, choices: Set<DirectoryFilterChoice>, creative: CreativeProfileStore) -> Bool {
        guard !choices.isEmpty else { return true }
        let details = creative.profile(forUserID: user.id)?.details
        let byFacet = Dictionary(grouping: choices, by: \.facet)
        for (facet, picks) in byFacet {
            let options = Set(picks.map(\.option))
            let hit: Bool
            switch facet {
            case gender:
                hit = options.contains { same($0, details?.actor.gender) }
            case age:
                hit = ActorDetails.ageBands.contains { band in
                    options.contains(band.label) && (details?.actor.overlapsAge(low: band.low, high: band.high) ?? false)
                }
            case height:
                if let inches = details?.actor.heightInches {
                    hit = ActorDetails.heightBands.contains { options.contains($0.label) && inches >= $0.low && inches <= $0.high }
                } else {
                    hit = false
                }
            case hair:
                hit = matchesLoose(options, value: details?.actor.hair ?? "", known: ActorDetails.hairColors)
            case eyes:
                hit = matchesLoose(options, value: details?.actor.eyes ?? "", known: ActorDetails.eyeColors)
            case role:
                hit = user.userTypes.contains { options.contains($0) }
            case instrument:
                hit = matchesList(options, values: details?.musician.instrumentList ?? [])
            case genre:
                hit = matchesList(options, values: details?.musician.genreList ?? [])
            default:
                hit = true
            }
            if !hit { return false }
        }
        return true
    }

    /// The active choices, in menu order, for a section footer: "Brown · 5'8\"–5'11\"".
    static func summary(of choices: Set<DirectoryFilterChoice>, facets: [DirectoryFacet]) -> String {
        facets
            .flatMap { facet in
                facet.options.filter { choices.contains(DirectoryFilterChoice(facet: facet.id, option: $0)) }
            }
            .joined(separator: " · ")
    }

    // MARK: - Helpers

    private static func same(_ a: String, _ b: String?) -> Bool {
        guard let b else { return false }
        return a.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    /// The fixed options plus any typed values they don't already cover
    /// (case-insensitive), keeping "Other" last.
    private static func merged(_ fixed: [String], seen: [String]) -> [String] {
        var result = fixed.filter { $0 != "Other" }
        for value in seen {
            let v = value.trimmingCharacters(in: .whitespaces)
            guard !v.isEmpty,
                  !result.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) else { continue }
            result.append(v)
        }
        if fixed.contains("Other") { result.append("Other") }
        return result
    }

    /// One typed value (hair, eyes) against the chosen options. "dark brown" also
    /// matches "Brown"; a value none of the known choices describe matches "Other".
    private static func matchesLoose(_ options: Set<String>, value: String, known: [String]) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard !v.isEmpty else { return false }
        for option in options {
            let o = option.lowercased()
            if o == "other" {
                let describedByKnown = known.contains { $0.lowercased() != "other" && v.contains($0.lowercased()) }
                if !describedByKnown { return true }
            } else if v == o || v.contains(o) {
                return true
            }
        }
        return false
    }

    /// A comma-separated list (instruments, genres) against the chosen options.
    private static func matchesList(_ options: Set<String>, values: [String]) -> Bool {
        values.contains { value in
            options.contains { option in
                option.caseInsensitiveCompare(value) == .orderedSame || value.lowercased().contains(option.lowercased())
            }
        }
    }
}
