//
//  FullScreenPosterView-9)Supporting.swift
//  Longhorn Artists Connect
//
//  Full screen view for viewing posters/thumbnails
//

import SwiftUI

// MARK: - Full Screen Poster View

struct FullScreenPosterView: View {
    let post: Submission
    let tintColor: Color
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea() // ⚙️ Background color
            
            // Poster image
            if let thumbnailData = post.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [
                            tintColor.opacity(0.55), // ⚙️ Gradient start opacity
                            tintColor.opacity(0.25)  // ⚙️ Gradient end opacity
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Close button in top right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold)) // ⚙️ Close button icon size
                            .foregroundStyle(.white) // ⚙️ Close button color
                            .frame(width: 44, height: 44) // ⚙️ Close button size
                            .background(
                                Circle()
                                    .fill(.black.opacity(0.5)) // ⚙️ Close button background
                            )
                            .contentShape(Circle())
                    }
                    .padding() // ⚙️ Close button padding
                }
                Spacer()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    FullScreenPosterView(
        post: Submission(id: UUID(), type: .film, title: "Sample Film", details: "A great movie"),
        tintColor: .orange
    )
}
