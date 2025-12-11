import SwiftUI

struct AddPersonView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var color: Color = .blue

    let onAdd: (Person) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                }
            }
            .navigationTitle("Add Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let person = Person(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                            color: color)
                        onAdd(person)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    AddPersonView { _ in }
}
