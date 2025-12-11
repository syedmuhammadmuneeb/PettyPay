import SwiftUI

struct GlassCard<Content: View>: View {
    let height: CGFloat
    @ViewBuilder private let content: Content

    init(height: CGFloat, @ViewBuilder content: () -> Content) {
        self.height = height
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay(
            content
                .padding()
        )
    }
}
