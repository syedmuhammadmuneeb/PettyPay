import SwiftUI
import UIKit

// Non-zooming, aspect-fit image inside a UIScrollView so we can keep consistent centering/inset behavior.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    @Binding var imageSize: CGSize   // reports the fitted size back to SwiftUI

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator

        // Disable zooming entirely
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 1.0
        scrollView.bouncesZoom = false

        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true

        context.coordinator.imageView = imageView
        scrollView.addSubview(imageView)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }

        let boundsSize = scrollView.bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }

        // Compute aspect-fit size inside the scrollView bounds
        let fittedSize = fittedAspectFitSize(for: image.size, in: boundsSize)
        guard fittedSize.width > 0, fittedSize.height > 0 else { return }

        // Layout: content equals fitted size
        imageView.frame = CGRect(origin: .zero, size: fittedSize)
        scrollView.contentSize = fittedSize

        // Center the content with insets so it appears aspect-fit on screen (no zoom)
        let insetX = max(0, (boundsSize.width - fittedSize.width) / 2)
        let insetY = max(0, (boundsSize.height - fittedSize.height) / 2)
        let newInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        if scrollView.contentInset != newInset {
            scrollView.contentInset = newInset
        }

        // Keep zoom at 1.0 (no zooming)
        if scrollView.zoomScale != 1.0 {
            scrollView.setZoomScale(1.0, animated: false)
        }

        // Report fitted size back to SwiftUI for overlay and crop math
        if imageSize != fittedSize {
            DispatchQueue.main.async {
                imageSize = fittedSize
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func fittedAspectFitSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return .zero
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        // No zooming: return nil to be safe
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Not used (zoom disabled), but keep content centered just in case
            guard let imageView = imageView else { return }
            let boundsSize = scrollView.bounds.size
            let contentSize = scrollView.contentSize

            let insetX = max(0, (boundsSize.width - contentSize.width) / 2)
            let insetY = max(0, (boundsSize.height - contentSize.height) / 2)
            let newInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
            if scrollView.contentInset != newInset {
                scrollView.contentInset = newInset
            }

            imageView.frame = CGRect(origin: .zero, size: contentSize)
        }
    }
}

