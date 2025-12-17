//
//  People.swift
//  PettyPay
//
//  Created by Syed Muhammad Muneeb on 09/12/25.
//

import SwiftUI

struct People: View {
    // MARK: - State
    @State private var allPeople: [Person] = []
    @State private var selectedPeople: [Person] = []
    @State private var isPresentingAddPerson: Bool = false
    @State private var isPresentingSelectPeople: Bool = false

    // Items interactions
    @State private var isEditingItems: Bool = false
    @State private var assigningItemID: UUID? = nil

    // Summary
    @State private var isPresentingSummary: Bool = false

    // Temporary local state for the mock bill name (no logic elsewhere)
    @State private var billName: String = ""

    @EnvironmentObject private var billStore: BillStore

    // Wrapper used for .sheet(item:)
    private struct AssignedItemContext: Identifiable {
        let id: UUID
        let index: Int
        let item: BillStore.BillItem
    }

    // MARK: - Palette (fixed order, cycles)
    private var avatarPalette: [Color] {
        [
            Color(hex: 0x708090), // Stone Grey (SlateGray)
            Color(hex: 0x4B5563), // Grey (dark grayish - Tailwind Gray 600)
            Color(hex: 0x0B0B0B), // Black (near-black to preserve gradients)
            Color(hex: 0x4E342E), // Mahogany (dark brown)
            Color(hex: 0x0B3D2E)  // Pine Tree (very dark green)
        ]
    }

    private func nextPaletteColor() -> Color {
        guard !avatarPalette.isEmpty else { return .blue }
        // Use total created people to pick next color; cycles with modulo
        let idx = allPeople.count % avatarPalette.count
        return avatarPalette[idx]
    }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(colors: [Color.black.opacity(0.2), Color.black.opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 16) {

                // Header: image + bill name
                GlassCard(height: 110) {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            .frame(width: 72, height: 72)
                            .overlay(
                                Group {
                                    if let billImage = billStore.billImage {
                                        Image(uiImage: billImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    } else {
                                        Image(systemName: "photo")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bill")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                TextField("Enter bill name", text: $billName)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }

                // Who's joining
                GlassCard(height: 180) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Who’s joining?")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Spacer()

                            HStack(spacing: 10) {
                                Button {
                                    isPresentingSelectPeople = true
                                } label: {
                                    Label("Edit", systemImage: "pencil.circle")
                                        .labelStyle(.iconOnly)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .tint(.primary)

                                Button {
                                    isPresentingAddPerson = true
                                } label: {
                                    Label("Add", systemImage: "plus.circle.fill")
                                        .labelStyle(.iconOnly)
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                                .tint(.primary)
                            }
                        }

                        if selectedPeople.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "person.2.circle")
                                        .font(.system(size: 36))
                                        .foregroundStyle(.secondary)
                                    Text("No one selected")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(selectedPeople) { person in
                                        VStack(spacing: 6) {
                                            AvatarCircle(person: person, size: 44)
                                            Text(person.name)
                                                .font(.caption2)
                                                .lineLimit(1)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 56)
                                        }
                                        .frame(minWidth: 56)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                removeFromSelected(person)
                                            } label: {
                                                Label("Remove from selection", systemImage: "minus.circle")
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.top, 8)
                }

                // Items area fills remaining space and scrolls independently
                GeometryReader { proxy in
                    VStack(spacing: 12) {
                        GlassCard(height: max(300, proxy.size.height - 80)) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("Items")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    // Edit toggle
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            isEditingItems.toggle()
                                        }
                                    } label: {
                                        Image(systemName: isEditingItems ? "checkmark.circle.fill" : "pencil.circle")
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                    .tint(.primary)
                                    .accessibilityLabel(isEditingItems ? "Done Editing Items" : "Edit Items")
                                }

                                if billStore.items.isEmpty {
                                    VStack(spacing: 8) {
                                        Text("Scan a bill to see items here")
                                            .foregroundStyle(.secondary)
                                            .font(.subheadline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.bottom, 8)
                                } else {
                                    // Header row
                                    HStack {
                                        Text("Descrizione")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("Prezzo")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 100, alignment: .trailing)
                                        // Keep space for trailing icon to align with rows
                                        Image(systemName: "person.crop.circle.badge.plus")
                                            .opacity(0)
                                            .frame(width: 28)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 4)

                                    // Scrollable items list (not SwiftUI List to keep container static)
                                    ScrollView(.vertical, showsIndicators: true) {
                                        LazyVStack(spacing: 10) {
                                            ForEach(Array(billStore.items.enumerated()), id: \.element.id) { index, item in
                                                HStack(spacing: 10) {
                                                    if isEditingItems {
                                                        // Delete control in edit mode
                                                        Button(role: .destructive) {
                                                            deleteItem(at: index)
                                                        } label: {
                                                            Image(systemName: "minus.circle.fill")
                                                                .foregroundStyle(.red)
                                                                .font(.title3)
                                                        }
                                                        .buttonStyle(.plain)
                                                    }

                                                    // 1) Description (and chips)
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(item.name)
                                                            .foregroundStyle(.primary)
                                                            .lineLimit(2)

                                                        if !item.assignedPeople.isEmpty {
                                                            let assigned = selectedPeople.filter { item.assignedPeople.contains($0.id) }
                                                            if !assigned.isEmpty {
                                                                ScrollView(.horizontal, showsIndicators: false) {
                                                                    HStack(spacing: 6) {
                                                                        ForEach(assigned) { person in
                                                                            Text(person.initials.uppercased())
                                                                                .font(.caption2.weight(.semibold))
                                                                                .padding(.horizontal, 8)
                                                                                .padding(.vertical, 4)
                                                                                .background(Capsule().fill(person.color.opacity(0.2)))
                                                                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                    .frame(maxWidth: .infinity, alignment: .leading)

                                                    // 2) Price
                                                    Text(formattedPrice(item.price))
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(.primary)
                                                        .frame(width: 100, alignment: .trailing)

                                                    // 3) Assign people button
                                                    Button {
                                                        assigningItemID = item.id
                                                    } label: {
                                                        Image(systemName: "person.crop.circle.badge.plus")
                                                            .font(.title3)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .tint(.primary)
                                                    .accessibilityLabel("Assign people to item")
                                                    .frame(width: 28, alignment: .trailing)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .fill(Color.white.opacity(0.06))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                                        )
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.bottom, 4)
                                    }
                                }
                            }
                            .padding()
                        }

                        // Modern native button pinned below items area
                        Button {
                            isPresentingSummary = true
                        } label: {
                            Text("Split")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.black)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.95), Color.black.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    }
                }
                .frame(maxHeight: .infinity) // occupy remaining space
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 12)
        }
        // Add person (minimal sheet: name only, color from palette)
        .sheet(isPresented: $isPresentingAddPerson) {
            MinimalAddPersonSheet { name in
                let color = nextPaletteColor()
                let person = Person(name: name, color: color)
                addPerson(person)
            }
            .presentationDetents([.medium])
        }
        // Select people
        .sheet(isPresented: $isPresentingSelectPeople) {
            SelectPeopleView(allPeople: allPeople, initiallySelected: selectedPeople) { updatedSelection in
                selectedPeople = updatedSelection
            }
            .presentationDetents([.medium, .large])
        }
        // Assign people to item
        .sheet(item: assigningItemBinding()) { (context: AssignedItemContext) in
            AssignPeopleSheet(
                allPeople: selectedPeople, // only allow from joining list
                assignedIDs: context.item.assignedPeople,
                onDone: { newAssigned in
                    updateAssignedPeople(for: context.index, with: newAssigned)
                    assigningItemID = nil
                },
                onCancel: {
                    assigningItemID = nil
                }
            )
            .presentationDetents([.medium, .large])
        }
        // Summary
        .sheet(isPresented: $isPresentingSummary) {
            let displayTitle = billName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Split" : billName
            SummarySheetView(title: displayTitle, people: selectedPeople, items: billStore.items)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Helpers (UI formatting)

    private func formattedPrice(_ decimal: Decimal?) -> String {
        guard let d = decimal else { return "" }
        let currencyCode = Locale.current.currency?.identifier ?? "EUR"
        return d.formatted(.currency(code: currencyCode))
    }

    // MARK: - Actions
    private func addPerson(_ person: Person) {
        allPeople.append(person)
        if !selectedPeople.contains(where: { $0.id == person.id }) {
            selectedPeople.append(person)
        }
    }

    private func removeFromSelected(_ person: Person) {
        selectedPeople.removeAll { $0.id == person.id }
        // Also remove from assigned in items
        for i in billStore.items.indices {
            billStore.items[i].assignedPeople.remove(person.id)
        }
    }

    private func deleteItem(at index: Int) {
        guard billStore.items.indices.contains(index) else { return }
        billStore.items.remove(at: index)
    }

    private func updateAssignedPeople(for index: Int, with newAssigned: Set<UUID>) {
        guard billStore.items.indices.contains(index) else { return }
        billStore.items[index].assignedPeople = newAssigned
    }

    // Binding helper to present sheet for assigning item
    private func assigningItemBinding() -> Binding<AssignedItemContext?> {
        Binding<AssignedItemContext?>(
            get: {
                guard let id = assigningItemID,
                      let idx = billStore.items.firstIndex(where: { $0.id == id }) else { return nil }
                let item = billStore.items[idx]
                return AssignedItemContext(id: id, index: idx, item: item)
            },
            set: { newValue in
                if newValue == nil {
                    assigningItemID = nil
                }
            }
        )
    }
}

// MARK: - Minimal Add Person Sheet (name only; color assigned by parent)

private struct MinimalAddPersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    // Now returns just the name; parent assigns color from palette
    let onAdd: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onAdd(trimmed)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Assign People Sheet

private struct AssignPeopleSheet: View {
    let allPeople: [Person] // pool to select from (those who joined)
    @State var assignedIDs: Set<UUID>
    var onDone: (Set<UUID>) -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(allPeople) { person in
                    HStack {
                        AvatarCircle(person: person, size: 28)
                        Text(person.name)
                        Spacer()
                        if assignedIDs.contains(person.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggle(person.id)
                    }
                }
            }
            .navigationTitle("Assign People")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(assignedIDs) }
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if assignedIDs.contains(id) {
            assignedIDs.remove(id)
        } else {
            assignedIDs.insert(id)
        }
    }
}

// MARK: - Summary Sheet

private struct SummarySheetView: View {
    let title: String
    let people: [Person]
    let items: [BillStore.BillItem]

    var body: some View {
        NavigationStack {
            List {
                Section("Per Person Totals") {
                    ForEach(people) { person in
                        let total = totalFor(personID: person.id)
                        HStack {
                            AvatarCircle(person: person, size: 28)
                            Text(person.name)
                            Spacer()
                            Text(formattedPrice(total))
                                .font(.body.weight(.semibold))
                        }
                    }
                }

                Section("Unassigned Items") {
                    ForEach(items.filter { $0.assignedPeople.isEmpty }) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(formattedPrice(item.price))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(title)
        }
    }

    private func totalFor(personID: UUID) -> Decimal {
        var sum = Decimal(0)
        for item in items {
            guard let price = item.price else { continue }
            guard !item.assignedPeople.isEmpty else { continue }
            if item.assignedPeople.contains(personID) {
                let share = price / Decimal(item.assignedPeople.count)
                sum += share
            }
        }
        return sum
    }

    private func formattedPrice(_ decimal: Decimal?) -> String {
        guard let d = decimal else { return "" }
        let currencyCode = Locale.current.currency?.identifier ?? "EUR"
        return d.formatted(.currency(code: currencyCode))
    }
}
