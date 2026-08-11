//
//  UploadProgressCenter.swift
//  Longhorn Artists Connect
//
//  Tracks the live CloudKit upload progress of a submission (keyed by its UUID) so
//  the submission forms can show a determinate progress wheel while media uploads,
//  a checkmark when it finishes, and an error + retry state if it fails.
//

import SwiftUI
import Combine

// MARK: - Upload Phase

/// The live state of a submission's media upload, as surfaced in the submission forms.
/// The absence of a phase (i.e. `nil`) means "not uploading" — the normal pick-a-file UI.
enum MediaUploadPhase: Equatable {
    /// Uploading, with a 0...1 fraction of how much has transferred.
    case uploading(Double)
    /// Finished successfully.
    case finished
    /// Failed with a user-facing message. The UI offers a Retry.
    case failed(String)
}

// MARK: - Upload Item

/// One in-flight submission upload, with enough metadata to render both the
/// submission form's status row and the Home-feed banner.
struct UploadItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let type: MediaType
    var phase: MediaUploadPhase
}

// MARK: - Upload Progress Center

/// A shared, main-actor store of in-flight submission uploads. `CloudKitManager`
/// reports byte-level progress here (keyed by the record name, which is the
/// submission's UUID), and `SubmissionStore` brackets each interactive upload with
/// `begin`/`finish`/`fail`. The submission forms and the Home feed observe it.
@MainActor
final class UploadProgressCenter: ObservableObject {
    static let shared = UploadProgressCenter()
    private init() {}

    /// In-flight uploads keyed by submission UUID. Missing entries mean "not uploading".
    @Published private(set) var items: [UUID: UploadItem] = [:]

    /// Marks an upload as started (0%). Call this before kicking off the save so the
    /// UI shows the wheel/bar immediately rather than after the first progress packet.
    func begin(_ id: UUID, title: String, type: MediaType) {
        items[id] = UploadItem(id: id, title: title, type: type, phase: .uploading(0))
    }

    /// Updates the fraction for an in-flight upload. `recordName` is the CloudKit
    /// record name, which for submissions equals the submission UUID; non-UUID names
    /// (e.g. user profiles) and untracked uploads are ignored. Never regresses a
    /// finished/failed upload back to "uploading".
    func report(recordName: String, fraction: Double) {
        guard let id = UUID(uuidString: recordName), let item = items[id] else { return }
        guard case .uploading = item.phase else { return }
        items[id]?.phase = .uploading(min(max(fraction, 0), 1))
    }

    func finish(_ id: UUID) {
        items[id]?.phase = .finished
    }

    func fail(_ id: UUID, _ message: String) {
        items[id]?.phase = .failed(message)
    }

    /// Stops tracking an upload (e.g. once the form has dismissed).
    func clear(_ id: UUID) {
        items[id] = nil
    }

    func phase(for id: UUID) -> MediaUploadPhase? {
        items[id]?.phase
    }

    /// Active (still uploading or failed) film/music/reel uploads, for the Home-feed
    /// banner. Finished uploads drop off once they've reached CloudKit.
    var homeFeedUploads: [UploadItem] {
        items.values
            .filter { [.film, .music, .reel].contains($0.type) && $0.phase != .finished }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

// MARK: - Circular Progress Ring

/// A small determinate "progress wheel": a ring that fills clockwise as the upload
/// transfers, with the percentage in the center.
struct CircularUploadProgress: View {
    /// 0...1 fraction uploaded.
    let fraction: Double
    var size: CGFloat = 34
    var lineWidth: CGFloat = 3

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: lineWidth)
            Circle()
                // Keep a sliver visible at 0% so it reads as a wheel, not an empty ring.
                .trim(from: 0, to: max(0.02, clamped))
                .stroke(Color.brandOrange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: clamped)

            Text("\(Int(clamped * 100))")
                .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Uploading")
        .accessibilityValue("\(Int(clamped * 100)) percent")
    }
}

// MARK: - Upload Status Row

/// The row shown in a submission form's "Upload" section while (and just after) the
/// post is uploading: a determinate wheel + percentage, a checkmark on success, or an
/// error message with a Retry button on failure.
struct MediaUploadStatusView: View {
    let phase: MediaUploadPhase
    var onRetry: () -> Void = {}

    var body: some View {
        switch phase {
        case .uploading(let fraction):
            HStack(spacing: 12) {
                CircularUploadProgress(fraction: fraction)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uploading…")
                        .foregroundStyle(.primary)
                    Text("\(Int(min(max(fraction, 0), 1) * 100))% complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)

        case .finished:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Upload complete")
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.vertical, 4)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("Upload failed")
                        .foregroundStyle(.primary)
                    Spacer()
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(Color.brandOrange)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Home Feed Banner

/// A banner pinned to the top of the Home feed while a film/music/reel the user just
/// posted is still uploading to CloudKit. Shows a determinate progress bar per
/// in-flight upload, or a failed state with a Retry. Renders nothing when idle.
struct HomeUploadBanner: View {
    @ObservedObject private var center = UploadProgressCenter.shared

    var body: some View {
        let uploads = center.homeFeedUploads
        Group {
            if !uploads.isEmpty {
                VStack(spacing: 10) {
                    ForEach(uploads) { item in
                        HomeUploadRow(item: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground))
                .overlay(alignment: .bottom) {
                    Divider()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: uploads.map(\.id))
    }
}

/// A single in-flight upload row inside `HomeUploadBanner`.
private struct HomeUploadRow: View {
    let item: UploadItem

    private var icon: String {
        switch item.type {
        case .film: return "film"
        case .music: return "music.note"
        case .reel: return "star.fill"
        default: return "arrow.up.circle"
        }
    }

    private var displayTitle: String {
        item.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : item.title
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.brandOrange)
                .frame(width: 24)

            switch item.phase {
            case .uploading(let fraction):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uploading \(item.type.rawValue.lowercased()) · \(displayTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: min(max(fraction, 0), 1))
                        .tint(Color.brandOrange)
                }
                Text("\(Int(min(max(fraction, 0), 1) * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

            case .finished:
                // Not shown (homeFeedUploads drops finished uploads), but the switch
                // must be exhaustive.
                Text("Posted · \(displayTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)

            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upload failed · \(displayTitle)")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button {
                    SubmissionStore_3_2.shared.retryUpload(id: item.id)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.brandOrange)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Preview

#Preview("Upload states") {
    List {
        Section("Uploading") {
            MediaUploadStatusView(phase: .uploading(0.42))
        }
        Section("Finished") {
            MediaUploadStatusView(phase: .finished)
        }
        Section("Failed") {
            MediaUploadStatusView(phase: .failed("The network connection was lost. Check your connection and try again."))
        }
    }
}
