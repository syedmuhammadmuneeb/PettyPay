import SwiftUI

struct CropOverlayView: View {
    let containerSize: CGSize       // The full GeometryReader container (view) size
    let imageSize: CGSize           // The displayed fitted image size inside the container
    @Binding var cropRect: CGRect   // In container coordinates

    // Handle sizes
    private let handleSize: CGFloat = 18
    private let handleHitSize: CGFloat = 44
    private let minCropSize: CGFloat = 60

    // Gesture state
    @State private var dragStartRect: CGRect = .zero
    @State private var resizeStartRect: CGRect = .zero
    @State private var activeCorner: Corner?

    // Flags to emulate onBegan once-per-gesture behavior
    @State private var hasStartedDrag = false
    @State private var hasStartedResize = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dimmed outside area
            Color.black.opacity(0.5)
                .mask(
                    Rectangle()
                        .fill(style: FillStyle(eoFill: true))
                        .overlay(
                            Rectangle()
                                .path(in: cropRect)
                                .fill(Color.black) // the hole
                        )
                )
                .allowsHitTesting(false)

            // Crop rectangle border + grid
            ZStack {
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                GridLines()
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .padding(0.5)
            }
            .frame(width: cropRect.width, height: cropRect.height)
            .position(x: cropRect.midX, y: cropRect.midY)
            .contentShape(Rectangle())
            .gesture(dragGestureForRect())

            // Corner handles with larger (invisible) hit areas
            ForEach(Corner.allCases, id: \.self) { corner in
                ZStack {
                    // Invisible larger tappable area
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: handleHitSize, height: handleHitSize)
                        .contentShape(Rectangle())
                        .gesture(resizeGesture(for: corner))
                    // Visible handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: handleSize, height: handleSize)
                        .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
                }
                .position(positionForCorner(corner))
            }
        }
        .onChange(of: imageSize) { _, _ in
            withAnimation(.easeOut(duration: 0.15)) {
                clampCropRectToImage()
            }
        }
        .onAppear {
            clampCropRectToImage()
        }
    }

    // MARK: - Gestures

    private func dragGestureForRect() -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !hasStartedDrag {
                    hasStartedDrag = true
                    dragStartRect = cropRect
                }
                var newRect = dragStartRect
                newRect.origin.x += value.translation.width
                newRect.origin.y += value.translation.height
                cropRect = softlyClampedRect(newRect)
            }
            .onEnded { _ in
                hasStartedDrag = false
                withAnimation(.easeOut(duration: 0.12)) {
                    cropRect = clampedRect(cropRect)
                }
            }
    }

    private func resizeGesture(for corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !hasStartedResize {
                    hasStartedResize = true
                    activeCorner = corner
                    resizeStartRect = cropRect
                }
                guard let corner = activeCorner else { return }
                var r = resizeStartRect
                let t = value.translation

                switch corner {
                case .topLeft:
                    r.origin.x += t.width
                    r.origin.y += t.height
                    r.size.width -= t.width
                    r.size.height -= t.height
                case .topRight:
                    r.origin.y += t.height
                    r.size.width += t.width
                    r.size.height -= t.height
                case .bottomLeft:
                    r.origin.x += t.width
                    r.size.width -= t.width
                    r.size.height += t.height
                case .bottomRight:
                    r.size.width += t.width
                    r.size.height += t.height
                }

                r = normalizedRect(r)
                r.size.width = max(r.width, minCropSize)
                r.size.height = max(r.height, minCropSize)

                cropRect = softlyClampedRect(r)
            }
            .onEnded { _ in
                hasStartedResize = false
                activeCorner = nil
                withAnimation(.easeOut(duration: 0.12)) {
                    cropRect = clampedRect(cropRect)
                }
            }
    }

    // MARK: - Geometry helpers

    private func imageFrameInContainer() -> CGRect {
        // The fitted image is centered in container
        CGRect(
            x: (containerSize.width - imageSize.width) / 2,
            y: (containerSize.height - imageSize.height) / 2,
            width: imageSize.width,
            height: imageSize.height
        )
    }

    // Soft clamp for in-gesture smoothness (allows slight overshoot then pulls back)
    private func softlyClampedRect(_ rect: CGRect) -> CGRect {
        let img = imageFrameInContainer()
        var r = rect

        // Ensure minimum size
        r.size.width = max(r.width, minCropSize)
        r.size.height = max(r.height, minCropSize)

        // Apply a gentle damping near edges
        let overshoot: CGFloat = 12 // px allowed outside before hard clamp on end
        if r.minX < img.minX - overshoot { r.origin.x = img.minX - overshoot }
        if r.minY < img.minY - overshoot { r.origin.y = img.minY - overshoot }
        if r.maxX > img.maxX + overshoot { r.origin.x = img.maxX + overshoot - r.width }
        if r.maxY > img.maxY + overshoot { r.origin.y = img.maxY + overshoot - r.height }

        return r
    }

    // Hard clamp within image frame
    private func clampedRect(_ rect: CGRect) -> CGRect {
        let img = imageFrameInContainer()
        var r = rect

        // Ensure minimum size
        r.size.width = max(r.width, minCropSize)
        r.size.height = max(r.height, minCropSize)

        if r.minX < img.minX { r.origin.x = img.minX }
        if r.minY < img.minY { r.origin.y = img.minY }
        if r.maxX > img.maxX { r.origin.x = img.maxX - r.width }
        if r.maxY > img.maxY { r.origin.y = img.maxY - r.height }

        return r
    }

    private func clampCropRectToImage() {
        cropRect = clampedRect(cropRect)
    }

    private func normalizedRect(_ rect: CGRect) -> CGRect {
        var r = rect
        if r.width < 0 {
            r.origin.x += r.width
            r.size.width = -r.width
        }
        if r.height < 0 {
            r.origin.y += r.height
            r.size.height = -r.height
        }
        return r
    }

    private func positionForCorner(_ corner: Corner) -> CGPoint {
        switch corner {
        case .topLeft:
            return CGPoint(x: cropRect.minX, y: cropRect.minY)
        case .topRight:
            return CGPoint(x: cropRect.maxX, y: cropRect.minY)
        case .bottomLeft:
            return CGPoint(x: cropRect.minX, y: cropRect.maxY)
        case .bottomRight:
            return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        }
    }

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    // Simple grid overlay shape (rule of thirds)
    private struct GridLines: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            // Vertical thirds
            let w = rect.width / 3
            p.move(to: CGPoint(x: rect.minX + w, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + w, y: rect.maxY))
            p.move(to: CGPoint(x: rect.minX + 2*w, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + 2*w, y: rect.maxY))
            // Horizontal thirds
            let h = rect.height / 3
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + h))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h))
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + 2*h))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 2*h))
            return p
        }
    }
}
