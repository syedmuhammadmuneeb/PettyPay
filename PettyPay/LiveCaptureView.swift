import SwiftUI
import AVFoundation
import UIKit

struct LiveCaptureView: View {
    @EnvironmentObject private var billStore: BillStore

    // Called after analysis completes successfully
    var onConfirmedAndAnalyzed: () -> Void = {}

    @State private var session = AVCaptureSession()
    @State private var isSessionConfigured = false
    @State private var photoOutput = AVCapturePhotoOutput()

    @State private var capturedImage: UIImage?
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            // Live camera or captured preview
            if let img = capturedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.05))
                    .clipped()
            } else {
                CameraPreview(session: session)
                    .ignoresSafeArea()
            }

            // Top bar
            VStack {
                HStack {
                    Spacer()
                    if billStore.isAnalyzing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .padding(10)
                            .background(.black.opacity(0.35), in: Capsule())
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)

                Spacer()

                // Bottom controls
                HStack(spacing: 22) {
                    // Retake (only visible after capture)
                    if capturedImage != nil {
                        ControlButton(systemName: "arrow.counterclockwise") {
                            capturedImage = nil
                        }
                    } else {
                        // Placeholder to keep layout balanced
                        Color.clear.frame(width: 56, height: 56)
                    }

                    // Shutter (capture) when no image; Checkmark (confirm) when captured
                    if capturedImage == nil {
                        ShutterButton(isBusy: isCapturing || billStore.isAnalyzing) {
                            capturePhoto()
                        }
                    } else {
                        ControlButton(systemName: "checkmark.circle.fill") {
                            confirmAndAnalyze()
                        }
                    }

                    // Spacer to balance layout
                    Color.clear.frame(width: 56, height: 56)
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            configureSessionIfNeeded()
            startSession()
        }
        .onDisappear {
            stopSession()
        }
    }

    // MARK: - Session setup

    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(photoOutput)

        // Prefer highest-quality photo capture
        photoOutput.isHighResolutionCaptureEnabled = true
        if #available(iOS 16.0, *) {
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        if let connection = photoOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        session.commitConfiguration()
        isSessionConfigured = true
    }

    private func startSession() {
        guard isSessionConfigured else { return }
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }

    private func stopSession() {
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
            }
        }
    }

    // MARK: - Capture & Analyze

    private func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            settings.isHighResolutionPhotoEnabled = true
            settings.flashMode = .off
            if #available(iOS 16.0, *) {
                settings.photoQualityPrioritization = .quality
            }
        }

        // Optional: try to stabilize exposure/focus briefly before capture
        lockExposureAndFocusTemporarily()

        let delegate = PhotoCaptureDelegate { image in
            DispatchQueue.main.async {
                self.isCapturing = false
                self.capturedImage = image
                if let img = image {
                    self.billStore.billImage = img
                }
            }
        }
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    private func confirmAndAnalyze() {
        guard let img = capturedImage else { return }
        // Lightweight preprocessing to speed OCR and improve quality
        let processed = preprocessForOCR(img)
        Task {
            await billStore.analyze(image: processed)
            if !billStore.items.isEmpty {
                onConfirmedAndAnalyzed()
            }
        }
    }

    private func lockExposureAndFocusTemporarily() {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try device.lockForConfiguration()
                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = true
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                device.unlockForConfiguration()
            } catch {
                // ignore
            }
        }
    }

    // MARK: - Preprocess

    private func preprocessForOCR(_ image: UIImage) -> UIImage {
        let normalized = image.normalizedUp()
        let downscaled = normalized.downscaleIfNeeded(maxDimension: 2000)
        let enhanced = downscaled.grayscaleAndBoostContrast()
        return enhanced
    }
}

// MARK: - Camera Preview

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

// MARK: - Photo capture delegate

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            print("Photo capture error: \(error)")
            completion(nil)
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image.normalizedUp())
    }
}

private struct ControlButton: View {
    let systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

                Image(systemName: systemName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ShutterButton: View {
    var isBusy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

                Circle()
                    .fill(isBusy ? Color.gray.opacity(0.6) : Color.white)
                    .frame(width: 58, height: 58)
            }
        }
        .disabled(isBusy)
        .buttonStyle(.plain)
    }
}

private extension UIImage {
    func normalizedUp() -> UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }

    func downscaleIfNeeded(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }

    func grayscaleAndBoostContrast() -> UIImage {
        guard let cg = self.cgImage else { return self }
        let ci = CIImage(cgImage: cg)
        // Desaturate + contrast
        let params: [String: Any] = [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.25
        ]
        let filtered = ci
            .applyingFilter("CIColorControls", parameters: params)
        let ctx = CIContext(options: nil)
        guard let outCG = ctx.createCGImage(filtered, from: filtered.extent) else { return self }
        return UIImage(cgImage: outCG, scale: scale, orientation: .up)
    }
}
