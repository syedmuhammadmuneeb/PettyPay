import SwiftUI

struct AvatarCircle: View {
    let person: Person
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(person.color.opacity(0.35)) // was 0.2, increased for contrast
            Text(person.initials.uppercased())
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().stroke(Color.white.opacity(0.26), lineWidth: 1) // slightly stronger stroke
        )
    }
}

#Preview {
    AvatarCircle(person: Person(name: "Alex Doe", color: .brown), size: 48)
        .padding()
        .background(.black)
        .previewLayout(.sizeThatFits)
}
