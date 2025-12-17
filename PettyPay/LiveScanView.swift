// LiveScanView.swift
import SwiftUI
import AVFoundation
import Vision
import UIKit

struct LiveScanView: View {
    @EnvironmentObject private var billStore: BillStore

    // Called when scanning has produced items
    var onItemsDetected: () -> Void = {}

    @State private var session = AVCaptureSession()
    @State private var isSessionConfigured = false
    @State private var analyzer = FrameAnalyzer()

    var body: some View {
        ZStack {
            CameraPreview(session: session)
                .ignoresSafeArea()

            // Optional overlay hint
            VStack {
                Spacer()
                Text("Point the camera at the receipt")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            configureSessionIfNeeded()
            startSession()
            analyzer.onThrottledFrame = { uiImage in
                Task { @MainActor in
                    await billStore.analyze(image: uiImage)
                    if !billStore.items.isEmpty {
                        onItemsDetected()
                    }
                }
            }
        }
        .onDisappear {
            stopSession()
        }
    }

    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .high

        // Input: back wide camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // Output: video frames
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_32BGRA]
        let queue = DispatchQueue(label: "LiveScan.VideoOutput")
        output.setSampleBufferDelegate(analyzer, queue: queue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)

        // Orient to portrait if possible
        output.connections.forEach { connection in
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
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
}

// MARK: - Camera Preview Layer

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

// MARK: - Frame Analyzer (throttles frames -> UIImage -> callback)

private final class FrameAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // Throttle to avoid calling Vision every frame
    private let throttleInterval: TimeInterval = 1.0
    private var lastAnalysisTime: TimeInterval = 0

    var onThrottledFrame: (UIImage) -> Void = { _ in }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        let now = CACurrentMediaTime()
        guard now - lastAnalysisTime >= throttleInterval else { return }
        lastAnalysisTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Convert to UIImage for reuse with existing BillStore.analyze(image:)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: .right) // portrait camera

        onThrottledFrame(uiImage)
    }
}
