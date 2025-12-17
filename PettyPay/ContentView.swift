//
//  ContentView.swift
//  PettyPay
//
//  Created by Syed Muhammad Muneeb on 09/12/25.
//

import SwiftUI
import VisionKit

struct ContentView: View {
    @StateObject private var billStore = BillStore()
    @State private var showResults = false
    @State private var showScanner = true // Present scanner immediately

    var body: some View {
        Group {
            if showResults {
                People()
                    .environmentObject(billStore)
            } else {
                // Minimal placeholder while scanner sheet is up
                Color.black.opacity(0.95)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 12) {
                            if billStore.isAnalyzing {
                                ProgressView("Analyzing…")
                                    .tint(.white)
                                    .foregroundStyle(.white)
                            } else {
                                Text("Opening Scanner…")
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            if let error = billStore.lastError, !error.isEmpty {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                                    .padding(.top, 4)
                            }
                        }
                    )
                    .sheet(isPresented: $showScanner) {
                        VisionKitScannerView(
                            onCancel: {
                                // If cancelled, reopen the scanner
                                showScanner = true
                            },
                            onScanComplete: { image in
                                Task { @MainActor in
                                    billStore.billImage = image
                                    await billStore.analyze(image: image)
                                    if !billStore.items.isEmpty {
                                        showResults = true
                                    } else {
                                        billStore.lastError = billStore.lastError ?? "No euro-priced items found. Try a closer, flatter shot."
                                        showScanner = true // reopen to try again
                                    }
                                }
                            },
                            onError: { _ in
                                // On error, reopen scanner
                                showScanner = true
                            }
                        )
                        .ignoresSafeArea()
                        .environmentObject(billStore)
                    }
                    .environmentObject(billStore)
            }
        }
    }
}

#Preview {
    ContentView()
}
