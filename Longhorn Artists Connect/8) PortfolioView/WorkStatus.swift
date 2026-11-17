import SwiftUI

enum WorkStatus: String, CaseIterable, Identifiable {
    case none = ""
    case lookingForWork = "Looking for Work"
    case openToCollaborate = "Open to Collabs"
    case busy = "Busy"

    var id: String { rawValue }

    init(storedValue: String) {
        self = WorkStatus(rawValue: storedValue) ?? .none
    }

    var title: String {
        self == .none ? "No Status" : rawValue
    }

    var color: Color {
        switch self {
        case .none: .secondary
        case .lookingForWork: .green
        case .openToCollaborate: .blue
        case .busy: .orange
        }
    }
}

struct WorkStatusPill: View {
    let status: WorkStatus

    var body: some View {
        if status != .none {
            HStack(spacing: 5) {
                Circle()
                    .fill(status.color)
                    .frame(width: 7, height: 7)
                Text(status.title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.15), in: Capsule())
            .foregroundStyle(status.color)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Status: \(status.title)")
        }
    }
}

/// The user's own status pill, tappable to change it in place. Shows the regular
/// `WorkStatusPill` when a status is set, or a dashed "Set Status" placeholder when
/// not, so there's always something to tap. Tapping opens a menu of every status;
/// picking one calls `onSelect` so the caller can persist it.
struct EditableWorkStatusPill: View {
    let status: WorkStatus
    let onSelect: (WorkStatus) -> Void

    var body: some View {
        Menu {
            ForEach(WorkStatus.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    if option == status {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            if status == .none {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("Set Status")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .foregroundStyle(.secondary)
            } else {
                WorkStatusPill(status: status)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status == .none ? "Set status" : "Status: \(status.title). Tap to change")
    }
}
