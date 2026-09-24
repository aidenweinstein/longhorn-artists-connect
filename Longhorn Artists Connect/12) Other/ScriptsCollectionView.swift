//
//  ScriptsCollectionView.swift
//  Longhorn Artists Connect  
//
//  Script collection for agents and talent scouts
//

import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import Combine
import Combine
import Combine

// MARK: - Script Model

struct Script: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var logline: String
    var genres: [String]
    var authors: [String]
    var pageCount: Int
    var projectStatus: String
    var shootDates: String
    var fileURL: URL?
    var uploadDate: Date
    var submittedBy: String
    
    init(
        id: UUID = UUID(),
        title: String,
        logline: String = "",
        genres: [String] = [],
        authors: [String] = [],
        pageCount: Int = 0,
        projectStatus: String = "",
        shootDates: String = "",
        fileURL: URL? = nil,
        uploadDate: Date = Date(),
        submittedBy: String = ""
    ) {
        self.id = id
        self.title = title
        self.logline = logline
        self.genres = genres
        self.authors = authors
        self.pageCount = pageCount
        self.projectStatus = projectStatus
        self.shootDates = shootDates
        self.fileURL = fileURL
        self.uploadDate = uploadDate
        self.submittedBy = submittedBy
    }
}

// MARK: - Scripts Collection View

struct ScriptsCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scriptManager = ScriptManager.shared
    @State private var searchText = ""
    @State private var selectedGenreFilter: String = "All"
    @State private var selectedStatusFilter: String = "All"
    @State private var selectedScript: Script?
    @State private var showScriptDetail = false
    @State private var scriptToPreview: URL?
    
    private let genreOptions = ["All", "Action", "Comedy", "Drama", "Horror", "Mystery", "Romance", "Sci-Fi", "Thriller", "Western", "Documentary"]
    private let statusOptions = ["All", "Casting & Crewing", "Casting", "Crewing", "In Production", "In Post-Production", "Releasing"]
    
    var filteredScripts: [Script] {
        var scripts = scriptManager.scripts
        
        // Filter by search text
        if !searchText.isEmpty {
            scripts = scripts.filter { script in
                script.title.localizedCaseInsensitiveContains(searchText) ||
                script.logline.localizedCaseInsensitiveContains(searchText) ||
                script.authors.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }
        }
        
        // Filter by genre
        if selectedGenreFilter != "All" {
            scripts = scripts.filter { $0.genres.contains(selectedGenreFilter) }
        }
        
        // Filter by status
        if selectedStatusFilter != "All" {
            scripts = scripts.filter { $0.projectStatus == selectedStatusFilter }
        }
        
        return scripts.sorted { $0.uploadDate > $1.uploadDate }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filters
                VStack(spacing: 12) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search scripts, authors...", text: $searchText, axis: .vertical)
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top, 12)
                    
                    // Filter pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Genre filter
                            Menu {
                                ForEach(genreOptions, id: \.self) { genre in
                                    Button {
                                        selectedGenreFilter = genre
                                    } label: {
                                        HStack {
                                            Text(genre)
                                            if selectedGenreFilter == genre {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "film")
                                        .font(.caption)
                                    Text(selectedGenreFilter)
                                        .font(.subheadline)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedGenreFilter == "All" ?
                                    Color.secondary.opacity(0.15) :
                                    Color.brandOrange
                                )
                                .foregroundStyle(selectedGenreFilter == "All" ? .primary : Color.white)
                                .clipShape(Capsule())
                            }
                            
                            // Status filter
                            Menu {
                                ForEach(statusOptions, id: \.self) { status in
                                    Button {
                                        selectedStatusFilter = status
                                    } label: {
                                        HStack {
                                            Text(status)
                                            if selectedStatusFilter == status {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.bar.doc.horizontal")
                                        .font(.caption)
                                    Text(selectedStatusFilter == "All" ? "Status" : selectedStatusFilter)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedStatusFilter == "All" ?
                                    Color.secondary.opacity(0.15) :
                                    Color.brandOrange
                                )
                                .foregroundStyle(selectedStatusFilter == "All" ? .primary : Color.white)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                }
                .background(Color(uiColor: .systemBackground))
                
                Divider()
                
                // Scripts list
                if scriptManager.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading scripts...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredScripts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: searchText.isEmpty && selectedGenreFilter == "All" && selectedStatusFilter == "All" ? "doc.text" : "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        
                        Text(searchText.isEmpty && selectedGenreFilter == "All" && selectedStatusFilter == "All" ? "No Scripts Available" : "No Results Found")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text(searchText.isEmpty && selectedGenreFilter == "All" && selectedStatusFilter == "All" ? "Scripts from project submissions will appear here" : "Try adjusting your filters or search terms")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredScripts) { script in
                                ScriptCard(script: script) {
                                    selectedScript = script
                                    showScriptDetail = true
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Scripts Collection")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showScriptDetail) {
                if let script = selectedScript {
                    ScriptDetailView(script: script)
                }
            }
        }
        .onAppear {
            scriptManager.loadScripts()
        }
    }
}

// MARK: - Script Card

struct ScriptCard: View {
    let script: Script
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with title and status
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(script.title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        if !script.authors.isEmpty {
                            Text("by \(script.authors.joined(separator: ", "))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if !script.projectStatus.isEmpty {
                        Text(script.projectStatus)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.brandOrange)
                            .clipShape(Capsule())
                    }
                }
                
                // Logline
                if !script.logline.isEmpty {
                    Text(script.logline)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                
                // Genres
                if !script.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(script.genres, id: \.self) { genre in
                                Text(genre)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.brandOrange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.brandOrange.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                
                Divider()
                
                // Footer info
                HStack {
                    if script.pageCount > 0 {
                        Label("\(script.pageCount) pages", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !script.shootDates.isEmpty {
                        Label(script.shootDates, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Script Detail View

struct ScriptDetailView: View {
    let script: Script
    @Environment(\.dismiss) private var dismiss
    @State private var showQuickLook = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(script.title)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        if !script.authors.isEmpty {
                            Text("Written by \(script.authors.joined(separator: ", "))")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        
                        if !script.submittedBy.isEmpty {
                            Text("Submitted by \(script.submittedBy)")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    // Status badge
                    if !script.projectStatus.isEmpty {
                        HStack {
                            Label(script.projectStatus, systemImage: "chart.bar.doc.horizontal")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.brandOrange)
                                .clipShape(Capsule())
                            
                            Spacer()
                        }
                    }
                    
                    Divider()
                    
                    // Logline
                    if !script.logline.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Logline")
                                .font(.headline)
                            Text(script.logline)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Genres
                    if !script.genres.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Genres")
                                .font(.headline)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(script.genres, id: \.self) { genre in
                                    Text(genre)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.brandOrange)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.brandOrange.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    
                    // Details grid
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Details")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            if script.pageCount > 0 {
                                DetailRow(icon: "doc.text", label: "Page Count", value: "\(script.pageCount) pages")
                            }
                            
                            if !script.shootDates.isEmpty {
                                DetailRow(icon: "calendar", label: "Shoot Dates", value: script.shootDates)
                            }
                            
                            DetailRow(icon: "clock", label: "Uploaded", value: formatDate(script.uploadDate))
                        }
                    }
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        if script.fileURL != nil {
                            Button {
                                showQuickLook = true
                            } label: {
                                Label("Read Script", systemImage: "book.pages")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.brandOrange)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.slash")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Script file not available")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showQuickLook) {
                if let url = script.fileURL {
                    QuickLookView(url: url)
                }
            }
        }
        .presentationDragIndicator(.hidden)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.brandOrange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = calculateLayout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = calculateLayout(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    private func calculateLayout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var positions: [CGPoint] = []
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        
        return (CGSize(width: width, height: currentY + lineHeight), positions)
    }
}

// MARK: - QuickLook View

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        
        let navController = UINavigationController(rootViewController: controller)
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, dismiss: dismiss)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let url: URL
        let dismiss: DismissAction
        
        init(url: URL, dismiss: DismissAction) {
            self.url = url
            self.dismiss = dismiss
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as QLPreviewItem
        }
        
        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            dismiss()
        }
    }
}

// MARK: - Script Manager

class ScriptManager: ObservableObject {
    static let shared = ScriptManager()
    
    @Published var scripts: [Script] = []
    @Published var isLoading = false
    
    private init() {
        loadSampleScripts()
    }
    
    func loadScripts() {
        isLoading = true
        
        // Load scripts from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "savedScripts"),
           let decoded = try? JSONDecoder().decode([Script].self, from: data) {
            scripts = decoded
        } else {
            // If no saved scripts, use sample data
            loadSampleScripts()
        }
        
        isLoading = false
    }
    
    func addScript(_ script: Script) {
        scripts.append(script)
        saveScripts()
    }
    
    func removeScript(_ script: Script) {
        scripts.removeAll { $0.id == script.id }
        saveScripts()
    }
    
    private func saveScripts() {
        if let encoded = try? JSONEncoder().encode(scripts) {
            UserDefaults.standard.set(encoded, forKey: "savedScripts")
        }
    }
    
    private func loadSampleScripts() {
        scripts = [
            Script(
                title: "The Last Stand",
                logline: "A gripping thriller about a detective's final case before retirement takes an unexpected turn into a web of corruption and betrayal.",
                genres: ["Thriller", "Crime", "Drama"],
                authors: ["Jane Doe", "John Smith"],
                pageCount: 112,
                projectStatus: "Casting & Crewing",
                shootDates: "May 1 - May 15, 2026",
                submittedBy: "Jane Doe"
            ),
            Script(
                title: "Summer Nights",
                logline: "A coming-of-age story set during one transformative summer in Austin, Texas. Three friends navigate love, loss, and the meaning of friendship.",
                genres: ["Drama", "Romance"],
                authors: ["Emma Davis"],
                pageCount: 98,
                projectStatus: "In Production",
                shootDates: "June 10 - June 24, 2026",
                submittedBy: "Emma Davis"
            ),
            Script(
                title: "Echoes of Tomorrow",
                logline: "In a dystopian future, a programmer discovers a way to communicate with the past and must prevent a catastrophic event that shaped their world.",
                genres: ["Sci-Fi", "Thriller"],
                authors: ["Michael Chen", "Sarah Williams"],
                pageCount: 125,
                projectStatus: "Casting",
                shootDates: "August 5 - August 25, 2026",
                submittedBy: "Michael Chen"
            ),
            Script(
                title: "The Coffee Shop Chronicles",
                logline: "A heartwarming comedy following the daily lives of baristas and regulars at a quirky Austin coffee shop where everyone knows your name and your drink order.",
                genres: ["Comedy", "Drama"],
                authors: ["Alex Martinez"],
                pageCount: 87,
                projectStatus: "Crewing",
                shootDates: "April 20 - May 5, 2026",
                submittedBy: "Alex Martinez"
            ),
            Script(
                title: "Whispers in the Woods",
                logline: "A group of college students on a camping trip in the Hill Country encounter something ancient and terrifying that has been waiting in the darkness.",
                genres: ["Horror", "Mystery"],
                authors: ["Tom Wilson", "Lisa Anderson"],
                pageCount: 95,
                projectStatus: "Casting & Crewing",
                shootDates: "October 15 - October 30, 2026",
                submittedBy: "Tom Wilson"
            ),
            Script(
                title: "Beyond the Frame",
                logline: "A documentary-style exploration of emerging filmmakers at UT Austin, capturing their creative journeys, struggles, and triumphs.",
                genres: ["Documentary"],
                authors: ["Chris Lee"],
                pageCount: 62,
                projectStatus: "In Post-Production",
                shootDates: "Completed",
                submittedBy: "Chris Lee"
            )
        ]
    }
}


// MARK: - Preview

#Preview("Scripts Collection") {
    ScriptsCollectionView()
}

#Preview("Script Detail") {
    ScriptDetailView(script: Script(
        title: "The Last Stand",
        logline: "A gripping thriller about a detective's final case before retirement takes an unexpected turn into a web of corruption and betrayal.",
        genres: ["Thriller", "Crime", "Drama"],
        authors: ["Jane Doe", "John Smith"],
        pageCount: 112,
        projectStatus: "Casting & Crewing",
        shootDates: "May 1 - May 15, 2026",
        submittedBy: "Jane Doe"
    ))
}
