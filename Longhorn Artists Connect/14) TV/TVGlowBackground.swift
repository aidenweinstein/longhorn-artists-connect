//
//  TVGlowBackground.swift
//  Longhorn Artists Connect
//
//  The glow behind every Apple TV screen: the look of the app icon and the website's
//  welcome page (web/components/SchoolGlows.tsx), with one glow per school in that
//  school's primary color.
//

import SwiftUI

struct TVGlowBackground: View {

    /// A school's glow: its color, how strong it is, and where on the screen it sits
    /// (unit coordinates). Dark colors need more strength to read on near-black.
    private struct Glow {
        let color: Color
        let strength: Double
        let center: UnitPoint
    }

    private static let glows: [Glow] = [
        // UT Austin burnt orange, top left.
        Glow(color: Color(red: 191 / 255, green: 87 / 255, blue: 0), strength: 0.32, center: UnitPoint(x: 0.18, y: 0.02)),
        // Michigan blue, top right.
        Glow(color: Color(red: 0, green: 39 / 255, blue: 76 / 255), strength: 0.85, center: UnitPoint(x: 0.84, y: 0.02)),
        // UC Berkeley blue, bottom left.
        Glow(color: Color(red: 0, green: 50 / 255, blue: 98 / 255), strength: 0.8, center: UnitPoint(x: 0.08, y: 0.96)),
        // USC cardinal, bottom right.
        Glow(color: Color(red: 153 / 255, green: 0, blue: 0), strength: 0.45, center: UnitPoint(x: 0.92, y: 0.96))
    ]

    var body: some View {
        GeometryReader { proxy in
            // Same falloff as the website: full strength at the center, about half at 40%, gone at the edge.
            let radius = proxy.size.height * 0.6
            ZStack {
                Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255)
                ForEach(Array(Self.glows.enumerated()), id: \.offset) { _, glow in
                    RadialGradient(
                        stops: [
                            .init(color: glow.color.opacity(glow.strength), location: 0),
                            .init(color: glow.color.opacity(glow.strength * 0.55), location: 0.4),
                            .init(color: glow.color.opacity(0), location: 1)
                        ],
                        center: glow.center,
                        startRadius: 0,
                        endRadius: radius
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    TVGlowBackground()
}
