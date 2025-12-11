import SwiftUI

struct AvatarBadge: View {
    let person: Person
    var size: CGFloat = 56

    var body: some View {
        VStack(spacing: 6) {
            AvatarCircle(person: person, size: size)
            Text(person.name)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(width: size * 1.4)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    HStack {
        AvatarBadge(person: Person(name: "Alex Doe"))
        AvatarBadge(person: Person(name: "Sam"), size: 48)
    }
    .padding()
    .background(.black)
    .previewLayout(.sizeThatFits)
}
