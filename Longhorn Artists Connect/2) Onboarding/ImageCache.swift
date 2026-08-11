//
//  ImageCache.swift
//  Longhorn Artists Connect
//
//  Centralized image caching for memory management
//

import UIKit
import SwiftUI

/// Centralized image cache to prevent loading duplicate thumbnails into memory
@MainActor
class ImageCache {
    static let shared = ImageCache()
    
    private var cache = NSCache<NSString, UIImage>()
    
    private init() {
        // ⚙️ Configure cache limits
        cache.countLimit = 50  // Maximum 50 images in cache
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB maximum memory usage
        
        print("🖼️ ImageCache initialized (limit: 50 images, 50MB)")
    }
    
    /// Get cached image for a given key
    /// - Parameter key: Unique identifier (typically filename or UUID)
    /// - Returns: Cached UIImage if available
    func image(for key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }
    
    /// Store image in cache
    /// - Parameters:
    ///   - image: UIImage to cache
    ///   - key: Unique identifier
    func setImage(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    /// Load image from file URL with caching
    /// - Parameter url: File URL to thumbnail
    /// - Returns: UIImage if successfully loaded
    func loadImage(from url: URL) -> UIImage? {
        let key = url.lastPathComponent
        
        // Check cache first
        if let cachedImage = image(for: key) {
            return cachedImage
        }
        
        // Load from file
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        
        // Cache for next time
        setImage(image, for: key)
        return image
    }
    
    /// Load image from MediaItem with caching
    /// - Parameter item: Any MediaItem with thumbnailURL
    /// - Returns: UIImage if available
    func loadThumbnail(for item: any MediaItem) -> UIImage? {
        guard let url = item.thumbnailURL else { return nil }
        return loadImage(from: url)
    }
    
    /// Remove specific image from cache
    /// - Parameter key: Unique identifier
    func removeImage(for key: String) {
        cache.removeObject(forKey: key as NSString)
    }
    
    /// Clear all cached images
    func clear() {
        cache.removeAllObjects()
        print("🧹 ImageCache cleared")
    }
    
    /// Get current memory usage estimate (approximate)
    var estimatedMemoryUsage: String {
        let count = cache.countLimit
        return "~\(count) images cached"
    }
}

// MARK: - SwiftUI AsyncImage Alternative

/// Cached async image view that loads from file system with memory management
struct CachedAsyncImage: View {
    let url: URL?
    let placeholder: Image?
    let contentMode: ContentMode
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    init(url: URL?,
         placeholder: Image? = nil,
         contentMode: ContentMode = .fill) {
        self.url = url
        self.placeholder = placeholder
        self.contentMode = contentMode
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                ProgressView()
            } else if let placeholder = placeholder {
                placeholder
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let url = url, image == nil else { return }
        isLoading = true
        
        // Load on background thread
        let loadedImage = await Task.detached(priority: .userInitiated) {
            await ImageCache.shared.loadImage(from: url)
        }.value
        
        await MainActor.run {
            image = loadedImage
            isLoading = false
        }
    }
}

// MARK: - View Extension for Easy Usage

extension View {
    /// Load thumbnail with automatic caching
    func cachedThumbnail(for item: any MediaItem) -> some View {
        self.modifier(CachedThumbnailModifier(item: item))
    }
}

struct CachedThumbnailModifier: ViewModifier {
    let item: any MediaItem
    @State private var image: UIImage?
    
    func body(content: Content) -> some View {
        content
            .task {
                if let url = item.thumbnailURL {
                    image = await Task.detached(priority: .userInitiated) {
                        await ImageCache.shared.loadImage(from: url)
                    }.value
                }
            }
    }
}
