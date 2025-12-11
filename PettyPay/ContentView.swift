//
//  ContentView.swift
//  PettyPay
//
//  Created by Syed Muhammad Muneeb on 09/12/25.
//

import SwiftUI
import PhotosUI
import UIKit

enum AppTab: Hashable {
    case scan
    case people
}

struct ContentView: View {
    @StateObject private var billStore = BillStore()
    @State private var selectedTab: AppTab = .scan

    var body: some View {
        TabView(selection: $selectedTab) {
            // Scan Tab
            ScanView(onFinishedAnalyzing: {
                // Switch to People tab after user confirms and analysis completes
                selectedTab = .people
            })
            .environmentObject(billStore)
            .tabItem {
                Label("Scan", systemImage: "camera.viewfinder")
            }
            .tag(AppTab.scan)

            // People Tab
            People()
                .environmentObject(billStore)
                .tabItem {
                    Label("People", systemImage: "person.2.fill")
                }
                .tag(AppTab.people)
        }
    }
}

// MARK: - Scan View
struct ScanView: View {
    @EnvironmentObject private var billStore: BillStore

    @State private var showCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var image: UIImage?

    // Cropping flow
    @State private var pendingImageForCrop: UIImage?
    @State private var showCropper = false

    // Callback to switch to People tab when analysis is done
    var onFinishedAnalyzing: () -> Void = {}

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.7)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Glass container for preview + actions
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 20, y: 8)

                        VStack(spacing: 16) {
                            // Preview
                            Group {
                                if let uiImage = image {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18)
                                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                        )
                                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity),
                                                                removal: .opacity))
                                } else {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                        .frame(height: 260)
                                        .overlay(
                                            VStack(spacing: 10) {
                                                Image(systemName: "camera.viewfinder")
                                                    .font(.system(size: 36, weight: .semibold))
                                                    .foregroundStyle(.secondary)
                                                Text("Ready to capture")
                                                    .foregroundStyle(.secondary)
                                            }
                                        )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 18)

                            // Inline controls when no image
                            if image == nil {
                                HStack(spacing: 16) {
                                    RoundGlassIconButton(systemName: "camera.fill", size: 56) {
                                        billStore.reset()
                                        showCamera = true
                                    }
                                    GlassPhotosPickerIcon(selection: $selectedPhotoItem, systemName: "photo.on.rectangle", size: 56)
                                }
                                .padding(.bottom, 20)
                            } else {
                                // Reserve space for overlay controls
                                Color.clear.frame(height: 84)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .overlay(alignment: .bottom) {
                        // Floating icon-only action bar when image is available
                        if image != nil {
                            GlassIconActionBar {
                                // Retake: reopen camera and reset
                                RoundGlassIconButton(systemName: "camera.rotate", size: 56) {
                                    let gen = UIImpactFeedbackGenerator(style: .light)
                                    gen.impactOccurred()
                                    billStore.reset()
                                    image = nil
                                    pendingImageForCrop = nil
                                    showCropper = false
                                    showCamera = true
                                }
                                // Crop existing image
                                RoundGlassIconButton(systemName: "crop", size: 56) {
                                    if let img = image {
                                        pendingImageForCrop = img
                                        showCropper = true
                                    }
                                }
                                // Select from library
                                GlassPhotosPickerIcon(selection: $selectedPhotoItem, systemName: "photo.on.rectangle", size: 56)
                                // Confirm/analyze ("OK")
                                RoundGlassIconButton(systemName: "checkmark.circle.fill", size: 56) {
                                    let gen = UINotificationFeedbackGenerator()
                                    gen.notificationOccurred(.success)
                                    // Analyze and store image when OK is pressed
                                    if let img = image {
                                        billStore.billImage = img
                                        Task {
                                            await billStore.analyze(image: img)
                                            let feedback = UIImpactFeedbackGenerator(style: .light)
                                            feedback.impactOccurred()
                                            // After analysis completes, switch to People tab
                                            await MainActor.run {
                                                onFinishedAnalyzing()
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }

                    // Analysis status
                    if billStore.isAnalyzing {
                        ProgressView("Analyzing...")
                            .padding(.top, 8)
                    } else if let err = billStore.lastError {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .padding(.top, 6)
                    }

                    // Secondary tip (optional)
                    if image == nil {
                        Text("Camera opens automatically")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 16)
                .padding(.bottom, 30)
            }
        }
        // Camera sheet
        .sheet(isPresented: $showCamera) {
            CameraPicker(image: $image)
                .ignoresSafeArea()
        }
        // Cropper sheet
        .sheet(isPresented: $showCropper) {
            if let img = pendingImageForCrop {
                ImageCropperView(image: img, onCancel: {
                    pendingImageForCrop = nil
                    showCropper = false
                }, onCropped: { cropped in
                    Task {
                        await MainActor.run {
                            image = cropped
                            pendingImageForCrop = nil
                            showCropper = false // Dismiss cropper when "Use" is pressed
                            billStore.billImage = cropped // Save cropped image to store
                        }
                        await billStore.analyze(image: cropped)
                        let gen = UIImpactFeedbackGenerator(style: .light)
                        gen.impactOccurred()
                        // After analysis completes, switch to People tab
                        await MainActor.run {
                            onFinishedAnalyzing()
                        }
                    }
                })
            }
        }
        // Auto open camera on first appear if no image
        .onAppear {
            if image == nil {
                showCamera = true
            }
        }
        // Handle PhotosPicker result
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.pendingImageForCrop = uiImage
                        self.showCropper = true
                        self.image = uiImage
                        billStore.reset()
                        billStore.billImage = uiImage
                    }
                }
            }
        }
        // When camera provides image, open cropper then analyze
        .onChange(of: image) { _, newImage in
            guard let img = newImage else { return }
            pendingImageForCrop = img
            showCropper = true
            billStore.reset()
            billStore.billImage = img
        }
    }
}

// MARK: - Glass Icon Controls

private struct RoundGlassIconButton: View {
    let systemName: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .frame(width: size, height: size)

                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct GlassIconActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 16) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        )
    }
}

private struct GlassPhotosPickerIcon: View {
    @Binding var selection: PhotosPickerItem?
    let systemName: String
    let size: CGFloat

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    .frame(width: size, height: size)

                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Camera Picker Wrapper (UIKit)
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            picker.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}

#Preview {
    ContentView()
}
