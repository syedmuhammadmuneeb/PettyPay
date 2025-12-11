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

    // Temporary local state for the mock bill name (no logic elsewhere)
    @State private var billName: String = ""

    @EnvironmentObject private var billStore: BillStore
    @State private var isEditingItems: Bool = false

    // Per-row people picker
    @State private var itemForPeoplePicker: BillStore.BillItem.ID?

    // Helper binding to resolve the selected BillItem from its ID.
    private var selectedBillItemBinding: Binding<BillStore.BillItem?> {
        Binding<BillStore.BillItem?>(
            get: {
                guard let id = itemForPeoplePicker else { return nil }
                return billStore.items.first(where: { $0.id == id })
            },
            set: { newValue in
                itemForPeoplePicker = newValue?.id
            }
        )
    }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(colors: [Color.black.opacity(0.2), Color.black.opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 24) {

                // Mock header: image square + bill name + edit button
                GlassCard(height: 110) {
                    HStack(spacing: 14) {
                        // Square placeholder for picture (left side)
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

                        // Bill info (right side)
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

                                Button {
                                    // No logic yet; purely visual
                                } label: {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary)
                                .accessibilityLabel("Edit bill name")
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }

                // Top glass bar
                GlassCard(height: 180) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Who’s joining?")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Spacer()

                            HStack(spacing: 10) {
                                // Edit button (opens selection UI)
                                Button {
                                    isPresentingSelectPeople = true
                                } label: {
                                    Label("Edit", systemImage: "pencil.circle")
                                        .labelStyle(.iconOnly)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .tint(.primary)
                                .accessibilityLabel("Edit selected people")

                                // Add button
                                Button {
                                    isPresentingAddPerson = true
                                } label: {
                                    Label("Add", systemImage: "plus.circle.fill")
                                        .labelStyle(.iconOnly)
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                                .tint(.primary)
                                .accessibilityLabel("Add person")
                            }
                        }

                        // Dynamic avatars
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
                                        AvatarBadge(person: person)
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

                // Main big card: Items list with custom row layout: name • qty • price • [checkbox] • [+]
                GlassCard(height: 380) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Items")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingItems.toggle()
                                }
                            } label: {
                                Label(isEditingItems ? "Done" : "Edit", systemImage: isEditingItems ? "checkmark.circle.fill" : "pencil.circle")
                                    .labelStyle(.iconOnly)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .tint(.primary)
                            .accessibilityLabel("Edit items")
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
                            List {
                                ForEach($billStore.items) { $item in
                                    HStack(spacing: 12) {
                                        // Name (leading)
                                        Text(item.name)
                                            .lineLimit(2)
                                            .foregroundStyle(.primary)

                                        Spacer(minLength: 8)

                                        // Quantity
                                        if isEditingItems {
                                            Stepper(value: $item.quantity, in: 1...99) {
                                                Text("x\(item.quantity)")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .frame(maxWidth: 160)
                                        } else {
                                            Text("x\(item.quantity)")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }

                                        // Unit Price (trailing-aligned)
                                        if let price = item.price {
                                            let currencyCode = Locale.current.currency?.identifier ?? "USD"
                                            Text(price.formatted(.currency(code: currencyCode)))
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .frame(minWidth: 80, alignment: .trailing)
                                        }

                                        // Select checkbox
                                        Button {
                                            item.isSelected.toggle()
                                        } label: {
                                            Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                                                .foregroundColor(item.isSelected ? .accentColor : .secondary)
                                                .imageScale(.medium)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(item.isSelected ? "Selected" : "Not selected")

                                        // Assign people
                                        Button {
                                            itemForPeoplePicker = item.id
                                        } label: {
                                            Image(systemName: "person.crop.circle.badge.plus")
                                                .imageScale(.medium)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Assign people")
                                    }
                                    .listRowBackground(Color.clear)
                                    .contentShape(Rectangle())
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            if let idx = billStore.items.firstIndex(where: { $0.id == item.id }) {
                                                billStore.items.remove(at: idx)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                .onMove { indices, newOffset in
                                    billStore.items.move(fromOffsets: indices, toOffset: newOffset)
                                }
                                .onDelete { offsets in
                                    billStore.items.remove(atOffsets: offsets)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .environment(\.editMode, .constant(isEditingItems ? .active : .inactive))
                        }
                    }
                    .padding()
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
        }
        // Sheet for adding a person
        .sheet(isPresented: $isPresentingAddPerson) {
            AddPersonView { newPerson in
                addPerson(newPerson)
            }
            .presentationDetents([.medium])
        }
        // Sheet for selecting people globally
        .sheet(isPresented: $isPresentingSelectPeople) {
            SelectPeopleView(allPeople: allPeople, initiallySelected: selectedPeople) { updatedSelection in
                selectedPeople = updatedSelection
            }
            .presentationDetents([.medium, .large])
        }
        // Per-row sheet for assigning people to a specific item
        .sheet(item: selectedBillItemBinding) { boundItem in
            let initiallySelected = allPeople.filter { boundItem.assignedPeople.contains($0.id) }
            SelectPeopleView(allPeople: allPeople, initiallySelected: initiallySelected) { updated in
                if let idx = billStore.items.firstIndex(where: { $0.id == boundItem.id }) {
                    billStore.items[idx].assignedPeople = Set(updated.map(\.id))
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Actions
    private func addPerson(_ person: Person) {
        allPeople.append(person)
        // Optionally auto-select newly added person
        if !selectedPeople.contains(where: { $0.id == person.id }) {
            selectedPeople.append(person)
        }
    }

    private func toggleSelection(for person: Person) {
        if let idx = selectedPeople.firstIndex(where: { $0.id == person.id }) {
            selectedPeople.remove(at: idx)
        } else {
            selectedPeople.append(person)
        }
    }

    private func removeFromSelected(_ person: Person) {
        selectedPeople.removeAll { $0.id == person.id }
    }

    private func deletePeople(at offsets: IndexSet) {
        let idsToDelete = offsets.map { allPeople[$0].id }
        allPeople.remove(atOffsets: offsets)
        selectedPeople.removeAll { idsToDelete.contains($0.id) }
    }
}

// ... (rest of file unchanged)

