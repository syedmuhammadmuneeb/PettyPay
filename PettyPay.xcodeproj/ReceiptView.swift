import SwiftUI

struct ReceiptView: View {
    @EnvironmentObject private var billStore: BillStore
    @State private var billName: String = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.2), Color.black.opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Bill header with image
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

                            TextField("Enter bill name", text: $billName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }

                        Spacer(minLength: 0)
                    }
                }

                // Items list: description, quantity, price only
                GlassCard(height: 420) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Items")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
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
                                ForEach(billStore.items) { item in
                                    HStack(spacing: 12) {
                                        // Description
                                        Text(item.name)
                                            .lineLimit(2)
                                            .foregroundStyle(.primary)

                                        Spacer(minLength: 8)

                                        // Quantity
                                        Text("x\(item.quantity)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)

                                        // Unit Price
                                        if let price = item.price {
                                            let currencyCode = Locale.current.currency?.identifier ?? "USD"
                                            Text(price.formatted(.currency(code: currencyCode)))
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .frame(minWidth: 80, alignment: .trailing)
                                        }
                                    }
                                    .listRowBackground(Color.clear)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                        }
                    }
                    .padding()
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
        }
    }
}
