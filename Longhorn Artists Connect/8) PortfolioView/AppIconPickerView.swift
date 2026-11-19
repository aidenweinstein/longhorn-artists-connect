//
//  AppIconPickerView.swift
//  Longhorn Artists Connect
//
//  More → App Icon: pick the home-screen icon. The default Nexus icon first,
//  then one in each school's colors (see SchoolColors.swift). Until the user
//  picks, the icon follows their school; a pick sticks across relaunches
//  (`SchoolAppIcon.choiceKey`).
//

import SwiftUI

// MARK: - Option

/// One row in the picker.
struct AppIconOption: Identifiable, Hashable {
    /// What `SchoolAppIcon.choiceKey` stores for this option.
    let id: String
    /// Row label, e.g. "Default" or "UC Berkeley".
    let title: String
    /// The alternate icon's asset name, or `nil` for the primary `AppIcon`.
    let iconName: String?
    /// Colors for the thumbnail if the bundled icon file can't be loaded.
    let bubble: Color
    let text: Color

    static let `default` = AppIconOption(id: SchoolAppIcon.defaultChoice, title: "Default",
                                         iconName: nil, bubble: .utBurntOrange, text: .white)

    /// Default first, then every themed school that has an icon.
    static let all: [AppIconOption] = [.default] + SchoolTheme.allSchools.compactMap { school in
        guard let iconName = school.theme.appIconName else { return nil }
        return AppIconOption(id: iconName,
                             title: OnboardingSchool.named(school.name)?.shortName ?? school.name,
                             iconName: iconName,
                             bubble: school.theme.bubble,
                             text: school.theme.text)
    }

    /// The option showing `iconName` (nil for the primary icon).
    static func matching(iconName: String?) -> AppIconOption {
        all.first { $0.iconName == iconName } ?? .default
    }

    /// The icon as it ships in the bundle. Xcode compiles each `.appiconset` into
    /// the asset catalog under its own name (CFBundleIcons lists them by
    /// `CFBundleIconName`), so the set's name loads it like any other image. Older
    /// toolchains flattened icons into loose files listed under
    /// `CFBundleIconFiles` instead, so those are tried first.
    var bundledImage: UIImage? {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let entry: [String: Any]?
        if let iconName {
            entry = (icons?["CFBundleAlternateIcons"] as? [String: Any])?[iconName] as? [String: Any]
        } else {
            entry = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        }
        if let files = entry?["CFBundleIconFiles"] as? [String], let file = files.last,
           let image = UIImage(named: file) {
            return image
        }
        return UIImage(named: iconName ?? SchoolAppIcon.defaultChoice)
    }
}

// MARK: - Picker

struct AppIconPickerView: View {
    @AppStorage(SchoolAppIcon.choiceKey) private var choice: String?
    @AppStorage("userSchool") private var userSchool = ""
    @AppStorage("isGuestUser") private var isGuestUser = false

    @State private var errorMessage: String?

    /// The icon on the home screen right now: the pick, or the school's.
    private var currentIconName: String? {
        let _ = choice // re-evaluate when the pick changes
        return SchoolAppIcon.iconName(for: AppTheme.theme(school: userSchool, isGuest: isGuestUser))
    }

    var body: some View {
        List {
            Section {
                ForEach(AppIconOption.all) { option in
                    Button {
                        select(option)
                    } label: {
                        row(for: option)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Until you choose, the icon matches your school.")
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't Change Icon", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(for option: AppIconOption) -> some View {
        HStack(spacing: 14) {
            thumbnail(for: option)
            Text(option.title)
                .foregroundStyle(.primary)
            Spacer()
            if option.iconName == currentIconName {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.utBrandOrange)
            }
        }
        .contentShape(Rectangle())
    }

    /// The icon at home-screen proportions. Falls back to a plain square in the
    /// school's colors if the bundled file isn't found (e.g. in a preview).
    private func thumbnail(for option: AppIconOption) -> some View {
        Group {
            if let image = option.bundledImage {
                Image(uiImage: image)
                    .resizable()
            } else {
                ZStack {
                    option.bubble
                    Circle()
                        .fill(option.text)
                        .padding(16)
                }
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
    }

    private func select(_ option: AppIconOption) {
        choice = option.id
        Task {
            do {
                try await SchoolAppIcon.set(iconName: option.iconName)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppIconPickerView()
    }
}
