//
//  CloudKitStatusBanner.swift
//  Longhorn Artists Connect
//
//  Banner that shows when CloudKit is unavailable
//

import SwiftUI

struct CloudKitStatusBanner: View {
    @ObservedObject var cloudKitManager = CloudKitManager.shared
    @State private var isDismissed = false
    
    var body: some View {
        if !cloudKitManager.isAvailable && !isDismissed {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "icloud.slash")
                        .font(.body)
                        .foregroundStyle(.white)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CloudKit Unavailable")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        
                        Text("Sign into iCloud to share posts")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            isDismissed = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Circle().fill(.white.opacity(0.2)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.orange)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview {
    VStack {
        CloudKitStatusBanner()
        Spacer()
    }
}
