import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom Grid Model

/// One tile in the Portfolio "Custom Grid": which post it shows and how wide it is,
/// as a fraction of the grid's width (1 = full width, 0.5 = half, 0.25 = quarter…).
struct PortfolioGridTile: Codable, Equatable {
    var id: String
    var widthFraction: Double
}

/// Encoding and reconciliation for the saved grid arrangement (JSON in @AppStorage).
/// This is fully independent of the List's `portfolioOrder` — editing one never
/// touches the other.
enum PortfolioGridStorage {
    static let defaultFraction = 0.5
    /// Smallest and largest tile widths, as fractions of the grid width. Anything in
    /// between is allowed — resizing is continuous.
    static let minFraction = 0.15
    static let maxFraction = 1.0
    /// Widths that tile a row exactly (e.g. three ⅓ posts side by side). A resize that
    /// comes close to one snaps onto it, so columns line up without pixel-perfect drags.
    static let snapFractions: [Double] = [0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.75, 1.0]
    static let snapDistance = 0.02

    static func decode(_ raw: String) -> [PortfolioGridTile] {
        guard let data = raw.data(using: .utf8),
              let tiles = try? JSONDecoder().decode([PortfolioGridTile].self, from: data) else { return [] }
        return tiles
    }

    static func encode(_ tiles: [PortfolioGridTile]) -> String {
        guard let data = try? JSONEncoder().encode(tiles) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reconciles the saved tiles with the posts currently on the portfolio: drops tiles
    /// whose posts are gone (or duplicated) and appends new posts, newest first, at the
    /// default size. New posts deliberately ignore the List order so the two stay separate.
    static func resolve(_ saved: [PortfolioGridTile], posts: [Submission]) -> [PortfolioGridTile] {
        let postIDs = Set(posts.map { $0.id.uuidString })
        var seen = Set<String>()
        var tiles = saved.filter { postIDs.contains($0.id) && seen.insert($0.id).inserted }
        let newPosts = posts
            .filter { !seen.contains($0.id.uuidString) }
            .sorted { $0.createdDate > $1.createdDate }
        for post in newPosts {
            tiles.append(PortfolioGridTile(id: post.id.uuidString, widthFraction: defaultFraction))
        }
        return tiles
    }

    /// Clamps a fraction to the allowed width range.
    static func adjusted(_ fraction: Double) -> Double {
        min(max(fraction, minFraction), maxFraction)
    }

    /// How far short of the grid's right edge, and how far past it, a resize still
    /// snaps flush to the edge. Pushing further past it lets the tile grow freely, so it
    /// no longer fits its row and drops to the next one.
    static let fillSnapBelow = 0.04
    static let fillSnapAbove = 0.06

    /// Clamps a fraction and snaps it onto a nearby clean width, if any. When
    /// `fillFraction` is given (the width that would reach the grid's right edge from
    /// the tile's spot), landing near it snaps the tile flush to that edge first.
    static func snapped(_ fraction: Double, fillFraction: Double? = nil) -> Double {
        let clamped = adjusted(fraction)
        if let fill = fillFraction,
           clamped > fill - fillSnapBelow, clamped < fill + fillSnapAbove {
            return fill
        }
        return snapFractions.first { abs($0 - clamped) < snapDistance } ?? clamped
    }
}

// MARK: - Custom Grid View

/// Thumbnail-only, edge-to-edge grid of the user's portfolio posts, each at its true
/// aspect ratio. In edit mode, tiles can be long-pressed and dragged to reorder, and
/// resized smoothly from their corner handle to any width from 15% of the grid up to
/// full width.
struct PortfolioCustomGridView: View {
    let submissions: [Submission]
    /// The saved arrangement (JSON of `[PortfolioGridTile]`), owned by the parent.
    @Binding var layoutRaw: String
    let isEditing: Bool
    /// The parent's horizontal padding, which the tiles extend past to reach the
    /// screen edges.
    var edgeBleed: CGFloat = 0
    /// The portfolio owner's roles on a post ("Director, Editor"), shown in the
    /// bottom-right corner of its tile. Return nil to leave a tile unlabeled.
    var roles: (Submission) -> String? = { _ in nil }
    let onOpen: (Submission) -> Void

    /// Working copy of the arrangement; persisted after each move and each resize.
    @State private var tiles: [PortfolioGridTile] = []
    /// Decoded thumbnails and their aspect ratios, cached so live resizing doesn't
    /// re-decode every image on every frame.
    @State private var images: [String: UIImage] = [:]
    @State private var aspects: [String: CGFloat] = [:]
    /// Tile currently being dragged to a new spot.
    @State private var draggingID: String?
    /// Snapshot taken when a tile's resize begins, keyed by tile ID.
    @State private var resizeStart: [String: ResizeStart] = [:]

    private struct ResizeStart {
        /// The tile's width fraction when the resize began.
        var fraction: Double
        /// The width that would carry the tile from where it sits to the grid's right
        /// edge — the "fill to edge" snap target.
        var fillFraction: Double
    }
    @State private var gridWidth: CGFloat = 0

    /// Thickness of the brand-color separator drawn where two posts meet (no spacing —
    /// it's centered on the shared edge, overlapping each post by half).
    private static let separatorWidth: CGFloat = 1.5
    /// Separator color: matches the page background (white in light mode, black in
    /// dark mode), so posts read as separated by a thin gap.
    private static var separatorColor: Color { Color(UIColor.systemBackground) }

    var body: some View {
        let byID = Dictionary(submissions.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: 8) {
            PortfolioTileLayout {
                ForEach(tiles, id: \.id) { tile in
                    if let submission = byID[tile.id] {
                        tileView(tile, submission)
                            .layoutValue(key: TileFractionKey.self, value: tile.widthFraction)
                            .layoutValue(key: TileAspectKey.self, value: aspects[tile.id] ?? TileAspectKey.defaultValue)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            // Separator lines only on edges shared by two posts — never on the grid's
            // outside edges or around empty patches.
            .overlay(alignment: .topLeading) {
                PortfolioGridPacker.separatorPath(between: currentFrames, lineWidth: Self.separatorWidth)
                    .fill(Self.separatorColor)
                    .allowsHitTesting(false)
            }
            // Fallback drop target so a drag released between tiles still ends cleanly.
            .onDrop(of: [.text], isTargeted: nil) { _ in
                draggingID = nil
                return true
            }
            // Bleed past the page's side padding so the grid runs edge to edge.
            .padding(.horizontal, -edgeBleed)
        }
        .onAppear { reload() }
        .onChange(of: submissions.map(\.id)) { reload() }
        .onChange(of: isEditing) { draggingID = nil }
    }

    /// Tile frames as the layout places them, used to draw the separators.
    private var currentFrames: [CGRect] {
        PortfolioGridPacker.frames(
            fractions: tiles.map { PortfolioGridStorage.adjusted($0.widthFraction) },
            aspects: tiles.map { aspects[$0.id] ?? TileAspectKey.defaultValue },
            width: gridWidth
        )
    }

    // MARK: Tiles

    @ViewBuilder
    private func tileView(_ tile: PortfolioGridTile, _ submission: Submission) -> some View {
        let shape = Rectangle()
        if isEditing {
            thumbnail(for: submission)
                .clipShape(shape)
                .overlay(alignment: .bottomTrailing) {
                    resizeHandle(for: tile, aspect: aspects[tile.id] ?? TileAspectKey.defaultValue)
                }
                .contentShape(.dragPreview, shape)
                .onDrag {
                    draggingID = tile.id
                    return NSItemProvider(object: tile.id as NSString)
                }
                .onDrop(of: [.text], delegate: TileDropDelegate(
                    targetID: tile.id,
                    tiles: $tiles,
                    draggingID: $draggingID,
                    commit: save
                ))
        } else {
            Button {
                onOpen(submission)
            } label: {
                thumbnail(for: submission)
                    .clipShape(shape)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func thumbnail(for submission: Submission) -> some View {
        thumbnailImage(for: submission)
            .overlay(alignment: .bottomTrailing) {
                // The owner's roles on this post, in black and white so they read on
                // any artwork. Hidden while editing because the resize handle sits in
                // the same corner.
                if !isEditing, let roles = roles(submission), !roles.isEmpty {
                    rolesLabel(roles)
                }
            }
    }

    /// Comma-separated roles caption: white text on a translucent black pill.
    private func rolesLabel(_ roles: String) -> some View {
        Text(roles)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
            .padding(6)
            .allowsHitTesting(false)
            .accessibilityLabel("Your roles: \(roles)")
    }

    @ViewBuilder
    private func thumbnailImage(for submission: Submission) -> some View {
        if let image = images[submission.id.uuidString] {
            // Tiles are sized to the image's own aspect ratio; fill only absorbs the
            // sub-point rounding of tile edges.
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: submission.type == .film ? "film" : "music.note")
                        .foregroundStyle(.secondary)
                )
        }
    }

    /// Corner handle: dragging it out or in grows or shrinks the tile smoothly (keeping
    /// its shape), and the rest of the grid reflows around it live.
    private func resizeHandle(for tile: PortfolioGridTile, aspect: CGFloat) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.brandOrange))
            .padding(4)
            .contentShape(Rectangle())
            // Global space: the handle moves as the tile grows, so a local-space drag
            // would measure against a moving origin.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let start = resizeStart[tile.id] ?? makeResizeStart(for: tile)
                        resizeStart[tile.id] = start
                        // The corner can move sideways or down; a vertical move of dy
                        // corresponds to a width change of dy × aspect. Follow whichever
                        // axis the finger moved further along.
                        let dx = value.translation.width
                        let dyAsWidth = value.translation.height * aspect
                        let delta = abs(dx) >= abs(dyAsWidth) ? dx : dyAsWidth
                        let fraction = PortfolioGridStorage.snapped(
                            start.fraction + delta / max(gridWidth, 1),
                            fillFraction: start.fillFraction
                        )
                        if let index = tiles.firstIndex(where: { $0.id == tile.id }),
                           tiles[index].widthFraction != fraction {
                            // A light tick when the tile clicks onto a clean width.
                            if fraction == start.fillFraction || PortfolioGridStorage.snapFractions.contains(fraction) {
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                            tiles[index].widthFraction = fraction
                        }
                    }
                    .onEnded { _ in
                        resizeStart[tile.id] = nil
                        save()
                    }
            )
    }

    /// Captures the tile's starting width and where it currently sits in its row, so
    /// the resize can snap its right edge flush to the grid's edge.
    private func makeResizeStart(for tile: PortfolioGridTile) -> ResizeStart {
        let width = max(gridWidth, 1)
        let frames = PortfolioGridPacker.frames(
            fractions: tiles.map { PortfolioGridStorage.adjusted($0.widthFraction) },
            aspects: tiles.map { aspects[$0.id] ?? TileAspectKey.defaultValue },
            width: width
        )
        let x = tiles.firstIndex(where: { $0.id == tile.id }).map { frames[$0].minX } ?? 0
        return ResizeStart(
            fraction: tile.widthFraction,
            fillFraction: PortfolioGridStorage.adjusted(Double((width - x) / width))
        )
    }

    // MARK: Persistence

    private func reload() {
        tiles = PortfolioGridStorage.resolve(PortfolioGridStorage.decode(layoutRaw), posts: submissions)
        var newImages: [String: UIImage] = [:]
        var newAspects: [String: CGFloat] = [:]
        for submission in submissions {
            let id = submission.id.uuidString
            if let data = submission.thumbnailData, let image = UIImage(data: data),
               image.size.width > 0, image.size.height > 0 {
                newImages[id] = image
                newAspects[id] = image.size.width / image.size.height
            }
        }
        images = newImages
        aspects = newAspects
    }

    private func save() {
        layoutRaw = PortfolioGridStorage.encode(tiles)
    }
}

// MARK: - Drop Delegate

/// Moves the dragged tile into the hovered tile's slot as soon as it enters, so the
/// grid rearranges live under the finger.
private struct TileDropDelegate: DropDelegate {
    let targetID: String
    @Binding var tiles: [PortfolioGridTile]
    @Binding var draggingID: String?
    let commit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID,
              let from = tiles.firstIndex(where: { $0.id == draggingID }),
              let to = tiles.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(.snappy) {
            tiles.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        commit()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        commit()
        return true
    }
}

// MARK: - Tile Layout

private struct TileFractionKey: LayoutValueKey {
    static let defaultValue: Double = PortfolioGridStorage.defaultFraction
}

private struct TileAspectKey: LayoutValueKey {
    static let defaultValue: CGFloat = 5.0 / 3.0
}

/// Edge-to-edge packing of tiles with no spacing. Frames are computed by
/// `PortfolioGridPacker`.
private struct PortfolioTileLayout: Layout {
    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        PortfolioGridPacker.frames(
            fractions: subviews.map { PortfolioGridStorage.adjusted($0[TileFractionKey.self]) },
            aspects: subviews.map { $0[TileAspectKey.self] },
            width: width
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let height = frames(for: subviews, width: width).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }
}

// MARK: - Packer

/// Places tiles, in order, at exactly the width they were set to and their true aspect
/// ratio. Each tile goes to the highest spot it fits without overlapping anything
/// (leftmost on ties), so later posts slide up into any space left beside or under
/// earlier ones. Where no post fits, a gap is left.
enum PortfolioGridPacker {
    /// Lines along every edge segment shared by two tiles, centered on the edge.
    /// Outside edges and edges bordering empty space get no line.
    static func separatorPath(between frames: [CGRect], lineWidth: CGFloat) -> Path {
        var path = Path()
        let half = lineWidth / 2
        for a in frames {
            for b in frames {
                // a's right edge against b's left edge.
                if abs(a.maxX - b.minX) < 0.5 {
                    let top = max(a.minY, b.minY), bottom = min(a.maxY, b.maxY)
                    if bottom - top > 0.5 {
                        path.addRect(CGRect(x: a.maxX - half, y: top, width: lineWidth, height: bottom - top))
                    }
                }
                // a's bottom edge against b's top edge.
                if abs(a.maxY - b.minY) < 0.5 {
                    let left = max(a.minX, b.minX), right = min(a.maxX, b.maxX)
                    if right - left > 0.5 {
                        path.addRect(CGRect(x: left, y: a.maxY - half, width: right - left, height: lineWidth))
                    }
                }
            }
        }
        return path
    }

    /// Overlap/edge tolerance in points, so rounding never bumps an exactly-fitting
    /// tile (like the third ⅓ post in a row) down to the next row.
    private static let epsilon: CGFloat = 0.5

    static func frames(fractions: [Double], aspects: [CGFloat], width: CGFloat) -> [CGRect] {
        guard width > 0 else { return fractions.map { _ in .zero } }
        var placed: [CGRect] = []

        for (index, fraction) in fractions.enumerated() {
            let tileWidth = min(width, max(1, CGFloat(fraction) * width))
            let aspect = index < aspects.count ? max(aspects[index], 0.1) : 5.0 / 3.0
            let tileHeight = tileWidth / aspect

            // A tile's best spot always has its left edge at 0, against another tile's
            // right edge, or flush with the right edge, and its top at 0 or on another
            // tile's bottom — so those are the only candidates to check.
            var xs: [CGFloat] = [0, width - tileWidth]
            var ys: [CGFloat] = [0]
            for rect in placed {
                xs.append(rect.maxX)
                ys.append(rect.maxY)
            }
            let sortedYs = Array(Set(ys)).sorted()
            let sortedXs = Array(Set(xs)).filter { $0 >= -epsilon && $0 + tileWidth <= width + epsilon }.sorted()

            var spot: CGRect?
            search: for y in sortedYs {
                for x in sortedXs {
                    let candidate = CGRect(x: max(0, x), y: y, width: tileWidth, height: tileHeight)
                    let inset = candidate.insetBy(dx: epsilon, dy: epsilon)
                    if !placed.contains(where: { $0.intersects(inset) }) {
                        spot = candidate
                        break search
                    }
                }
            }
            // Below everything always fits; only reached if the search found nothing.
            let bottom = placed.map(\.maxY).max() ?? 0
            placed.append(spot ?? CGRect(x: 0, y: bottom, width: tileWidth, height: tileHeight))
        }

        // Round edges consistently so tiles that touch meet with no hairline seam.
        return placed.map { rect in
            let x0 = rect.minX.rounded()
            let x1 = min(width, rect.maxX.rounded())
            let y0 = rect.minY.rounded()
            let y1 = rect.maxY.rounded()
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }
}
