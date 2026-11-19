//
//  OnboardingSchools.swift
//  Longhorn Artists Connect
//
//  The schools offered in onboarding, the role a member holds there, and which
//  email domain each role verifies with.
//

import Foundation

// MARK: - School Role

/// What the member is at their school, picked on `SchoolRolePage`.
/// - **Student** — verifies a student address, then details and tags.
/// - **Professor** — verifies a faculty address, then details (no tags).
/// - **Alumni** — no school email to verify; gives a name and phone number instead.
enum SchoolRole: String, CaseIterable, Identifiable {
    case student = "Student"
    case professor = "Professor"
    case alumni = "Alumni"

    var id: String { rawValue }

    /// Button copy on `SchoolRolePage`.
    var choiceLabel: String {
        switch self {
        case .student: return "I am a student"
        case .professor: return "I am a professor"
        case .alumni: return "I am an alumni"
        }
    }

    /// UserDefaults / `@AppStorage` key for the signed-in account's role.
    static let storageKey = "schoolRole"

    /// The signed-in account's role, or nil for accounts that never picked one.
    static var current: SchoolRole? {
        SchoolRole(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "")
    }
}

// MARK: - Onboarding School

/// One school on the "Select your school" page.
///
/// `name` must match the display name in `SchoolScope.registeredSchools` (and a
/// `SchoolTheme`); the domains must exist in the verification service's
/// `school_domains` table, or codes can't be sent.
struct OnboardingSchool: Identifiable, Hashable {
    let name: String
    /// Label on the school button.
    let shortName: String
    let studentDomain: String
    let facultyDomain: String
    /// Placeholder for the part before "@", e.g. "eid".
    let idPlaceholder: String

    var id: String { name }

    /// The domain a role must verify with, or nil for roles that don't verify.
    func domain(for role: SchoolRole) -> String? {
        switch role {
        case .student: return studentDomain
        case .professor: return facultyDomain
        case .alumni: return nil
        }
    }

    /// Every domain a member of this school could have verified with — used by
    /// Sign-In, where we don't yet know whether they're a student or professor.
    var allDomains: [String] {
        studentDomain == facultyDomain ? [studentDomain] : [studentDomain, facultyDomain]
    }

    static let all: [OnboardingSchool] = [
        // UT issues students EID@my.utexas.edu and faculty/staff EID@austin.utexas.edu.
        OnboardingSchool(name: UserProfileModel.utSchoolName, shortName: "UT Austin",
                         studentDomain: "my.utexas.edu", facultyDomain: "austin.utexas.edu",
                         idPlaceholder: "eid"),
        OnboardingSchool(name: UserProfileModel.berkeleySchoolName, shortName: "UC Berkeley",
                         studentDomain: "berkeley.edu", facultyDomain: "berkeley.edu",
                         idPlaceholder: "calnet id"),
        OnboardingSchool(name: "USC", shortName: "USC",
                         studentDomain: "usc.edu", facultyDomain: "usc.edu",
                         idPlaceholder: "username"),
        OnboardingSchool(name: "Texas A&M", shortName: "Texas A&M",
                         studentDomain: "tamu.edu", facultyDomain: "tamu.edu",
                         idPlaceholder: "netid"),
        OnboardingSchool(name: "Cal Poly SLO", shortName: "Cal Poly SLO",
                         studentDomain: "calpoly.edu", facultyDomain: "calpoly.edu",
                         idPlaceholder: "username"),
        // Ohio State addresses are lastname.#@osu.edu for students and staff alike.
        OnboardingSchool(name: "Ohio State", shortName: "Ohio State",
                         studentDomain: "osu.edu", facultyDomain: "osu.edu",
                         idPlaceholder: "lastname.#"),
        // UVA addresses are computingID@virginia.edu.
        OnboardingSchool(name: "UVA", shortName: "UVA",
                         studentDomain: "virginia.edu", facultyDomain: "virginia.edu",
                         idPlaceholder: "computing id"),
        OnboardingSchool(name: "UC Santa Barbara", shortName: "UCSB",
                         studentDomain: "ucsb.edu", facultyDomain: "ucsb.edu",
                         idPlaceholder: "netid")
    ]

    /// Schools that aren't offered in onboarding but that existing accounts may
    /// have on file (they're in `SchoolScope.registeredSchools`). Listed here so
    /// verification can pin their members to the school's domain too, instead
    /// of accepting any address. Domains match verification-service/seed/schools.sql.
    static let notOffered: [OnboardingSchool] = [
        // Michigan came off the sign-in list on 2026-11-19; its existing
        // accounts still verify with @umich.edu.
        OnboardingSchool(name: "University of Michigan", shortName: "UMich",
                         studentDomain: "umich.edu", facultyDomain: "umich.edu",
                         idPlaceholder: "uniqname"),
        OnboardingSchool(name: "NYU", shortName: "NYU",
                         studentDomain: "nyu.edu", facultyDomain: "nyu.edu",
                         idPlaceholder: "netid"),
        OnboardingSchool(name: "DePaul", shortName: "DePaul",
                         studentDomain: "depaul.edu", facultyDomain: "depaul.edu",
                         idPlaceholder: "username"),
        OnboardingSchool(name: "BU", shortName: "BU",
                         studentDomain: "bu.edu", facultyDomain: "bu.edu",
                         idPlaceholder: "username")
    ]

    /// Every school a member could have on file, whether or not onboarding
    /// still offers it. Use this — not `all` — when resolving a stored school.
    static var verifiable: [OnboardingSchool] { all + notOffered }

    static func named(_ name: String) -> OnboardingSchool? {
        verifiable.first { $0.name == name }
    }
}
