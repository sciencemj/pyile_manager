//
//  GlassCard.swift
//  pyile_manager
//
//  Reusable liquid glass container component
//

import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Color.primary.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
    }
}

#Preview {
    GlassCard {
        VStack(alignment: .leading, spacing: 8) {
            Text("Liquid Glass Card")
                .font(.headline)
            Text("This is a reusable glass card component with blur effect and subtle borders.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding()
    .frame(width: 300)
}
