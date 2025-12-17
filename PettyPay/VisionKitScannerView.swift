import SwiftUI
import VisionKit
import UIKit

struct VisionKitScannerView: UIViewControllerRepresentable {
    typealias UIViewControllerType = VNDocumentCameraViewController

    let onCancel: () -> Void
    let onScanComplete: (UIImage) -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: VisionKitScannerView

        init(_ parent: VisionKitScannerView) {
            self.parent = parent
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // Combine pages into a single tall image or just use first page.
            // Here we use the first page for simplicity. You can change to merge if needed.
            guard scan.pageCount > 0 else {
                parent.onCancel()
                return
            }
            let image = scan.imageOfPage(at: 0)
            parent.onScanComplete(image)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onError(error)
        }
    }
}
