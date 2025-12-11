import SwiftUI
import UIKit

struct ImageCropperView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onCropped: (UIImage) -> Void

    @State private var cropRect: CGRect = .zero
    @State private var imageSize: CGSize = .zero       // fitted size inside the container
    @State private var containerSize: CGSize = .zero
    @State private var initializedFromImageSize = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()

                    // Non-zooming, pure SwiftUI aspect-fit image that fills the available space visually.
                    // We compute the fitted size and center it manually to match cropping math.
                    GeometryReader { inner in
                        let container = inner.size
                        let fitted = fittedAspectFitSize(for: image.size, in: container)
                        // Report sizes to state for overlay and crop math
                        Color.clear
                            .onAppear {
                                containerSize = container
                                updateImageSizeIfNeeded(fitted)
                            }
                            .onChange(of: container) { _, newValue in
                                containerSize = newValue
                                let newFitted = fittedAspectFitSize(for: image.size, in: newValue)
                                updateImageSizeIfNeeded(newFitted)
                            }

                        // Centered fitted image
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: container.width / 2, y: container.height / 2)
                    }
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        // Visible, draggable, resizable crop overlay
                        CropOverlayView(containerSize: geo.size, imageSize: imageSize, cropRect: $cropRect)
                    }
                }
                .onAppear {
                    containerSize = geo.size
                }
                .onChange(of: geo.size) { _, newSize in
                    containerSize = newSize
                }
                .onChange(of: imageSize) { _, newSize in
                    // Initialize crop rect relative to the fitted image frame exactly once.
                    guard newSize.width > 0, newSize.height > 0 else { return }
                    guard !initializedFromImageSize else { return }
                    initializedFromImageSize = true

                    let imgFrame = CGRect(
                        x: (geo.size.width - newSize.width) / 2,
                        y: (geo.size.height - newSize.height) / 2,
                        width: newSize.width,
                        height: newSize.height
                    )

                    // Start with a centered rectangle inside the visible image.
                    let targetWidth = imgFrame.width * 0.8
                    let targetHeight = min(imgFrame.height * 0.8, targetWidth * 0.75) // ~4:3 if possible
                    let w = min(targetWidth, imgFrame.width)
                    let h = min(targetHeight, imgFrame.height)

                    cropRect = CGRect(
                        x: imgFrame.midX - w/2,
                        y: imgFrame.midY - h/2,
                        width: w,
                        height: h
                    )
                }
            }
            .navigationTitle("Crop")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        guard let cropped = cropImage(image: image,
                                                      cropRectInView: cropRect,
                                                      fittedImageSizeInView: imageSize,
                                                      containerSize: containerSize) else {
                            onCancel()
                            return
                        }
                        onCropped(cropped)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func updateImageSizeIfNeeded(_ fitted: CGSize) {
        guard fitted != .zero else { return }
        if imageSize != fitted {
            imageSize = fitted
        }
    }

    private func fittedAspectFitSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return .zero
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    // Convert cropRectInView (container coordinates) to pixel coordinates.
    private func cropImage(image: UIImage,
                           cropRectInView: CGRect,
                           fittedImageSizeInView: CGSize,
                           containerSize: CGSize) -> UIImage? {

        guard fittedImageSizeInView.width > 0, fittedImageSizeInView.height > 0 else { return nil }

        // Fitted image frame centered in the container
        let imageFrameInView = CGRect(
            x: (containerSize.width - fittedImageSizeInView.width) / 2,
            y: (containerSize.height - fittedImageSizeInView.height) / 2,
            width: fittedImageSizeInView.width,
            height: fittedImageSizeInView.height
        )

        // Crop rect relative to the fitted image frame
        let relative = CGRect(
            x: cropRectInView.minX - imageFrameInView.minX,
            y: cropRectInView.minY - imageFrameInView.minY,
            width: cropRectInView.width,
            height: cropRectInView.height
        )

        // Clamp to fitted image bounds
        let fittedBounds = CGRect(origin: .zero, size: fittedImageSizeInView)
        guard relative.intersects(fittedBounds) else { return nil }

        let clamped = CGRect(
            x: max(0, relative.minX),
            y: max(0, relative.minY),
            width: min(relative.width, fittedBounds.width - max(0, relative.minX)),
            height: min(relative.height, fittedBounds.height - max(0, relative.minY))
        )

        // Scale to pixel coordinates of the original image
        guard let cg = image.cgImage else { return nil }
        let scaleX = CGFloat(cg.width) / fittedImageSizeInView.width
        let scaleY = CGFloat(cg.height) / fittedImageSizeInView.height

        let pixelRect = CGRect(
            x: clamped.minX * scaleX,
            y: clamped.minY * scaleY,
            width: clamped.width * scaleX,
            height: clamped.height * scaleY
        )

        guard let croppedCG = cg.cropping(to: pixelRect.integral) else { return nil }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }
}

