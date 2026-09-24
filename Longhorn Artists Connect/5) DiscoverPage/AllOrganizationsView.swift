//
//  AllOrganizationsView.swift
//  Longhorn Artists Connect
//
//  The "Organizations" page reached from the Discover top bar: every student
//  organization on one screen. Tapping an org opens its own page.
//  Extracted from DiscoverView.swift.
//

import SwiftUI
import CloudKit
import Combine

// MARK: - Organizations List

/// The "Organizations" page reached from the Discover top bar. All orgs fit on one
/// non-scrollable screen, splitting the height evenly so each card shrinks as more
/// orgs are added. Tapping an org opens its own page.
struct OrganizationsView: View {
    @ObservedObject private var store: OrganizationStore = .shared
    /// The org whose page is presented as a bottom sheet (nil = none).
    @State private var selectedOrg: Organization?

    var body: some View {
        NavigationStack {
            Group {
                if store.organizations.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Uniform compact cards (all the same height), scrolling list.
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(store.organizations) { org in
                                Button {
                                    selectedOrg = org
                                } label: {
                                    OrganizationCard(organization: org)
                                        .frame(maxWidth: .infinity)
                                        // Same height for every card — fits a 1-line name
                                        // plus up to 2 lines of description.
                                        .frame(height: 96)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    // Org pages present from the bottom (no back button); swipe down to close.
                    .sheet(item: $selectedOrg) { org in
                        NavigationStack { OrganizationPageView(organization: org) }
                            .presentationDragIndicator(.hidden)
                    }
                }
            }
            // Slightly-off background (like the Directory's grouped list) so the org
            // cards read as sitting on a subtle surface rather than pure white.
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Organizations")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Organizations Previews

#if DEBUG

/// The four seed orgs with sample descriptions, for previews.
private let previewOrganizations: [Organization] = [
    Organization(id: "collective", name: "Collective",
                 description: "A creative studio.",
                 profileImageData: nil, order: 0),
    Organization(id: "incubator", name: "Incubator",
                 description: "A select group of students creating five original pilots.",
                 profileImageData: nil, order: 1),
    Organization(id: "dka", name: "DKA",
                 description: "Delta Kappa Alpha — national professional cinematic society.",
                 profileImageData: nil, order: 2),
    Organization(id: "the-new-project", name: "The New Project",
                 description: "Mulimedia creative collective/agency - redefining creative spaces at UT Austin.",
                 profileImageData: nil, order: 3)
]

/// Main Organizations page (the list reached from the Discover top bar).
#Preview("Organizations — List") {
    OrganizationStore.shared.organizations = previewOrganizations
    return OrganizationsView()
}

#Preview("Org — Collective") {
    NavigationStack { OrganizationPageView(organization: previewOrganizations[0]) }
}

#Preview("Org — Incubator") {
    NavigationStack { OrganizationPageView(organization: previewOrganizations[1]) }
}

#Preview("Org — DKA") {
    NavigationStack { OrganizationPageView(organization: previewOrganizations[2]) }
}

#Preview("Org — The New Project") {
    NavigationStack { OrganizationPageView(organization: previewOrganizations[3]) }
}

#endif
