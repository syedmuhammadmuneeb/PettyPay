import SwiftUI

struct SelectPeopleView: View {
    @Environment(\.dismiss) private var dismiss

    let allPeople: [Person]
    let initiallySelected: [Person]
    let onDone: ([Person]) -> Void

    @State private var selection: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(allPeople) { person in
                    HStack(spacing: 12) {
                        AvatarCircle(person: person, size: 32)
                        Text(person.name)
                        Spacer()
                        if selection.contains(person.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggle(person)
                    }
                }
            }
            .navigationTitle("Select People")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let selected = allPeople.filter { selection.contains($0.id) }
                        onDone(selected)
                        dismiss()
                    }
                }
            }
            .onAppear {
                selection = Set(initiallySelected.map(\.id))
            }
        }
    }

    private func toggle(_ person: Person) {
        if selection.contains(person.id) {
            selection.remove(person.id)
        } else {
            selection.insert(person.id)
        }
    }
}

#Preview {
    let sample = [
        Person(name: "Alex Doe"),
        Person(name: "Sam Lee", color: .green),
        Person(name: "Jordan")
    ]
    return SelectPeopleView(allPeople: sample, initiallySelected: [sample[0]]) { _ in }
}
