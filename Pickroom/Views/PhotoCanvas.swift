import SwiftUI

struct PhotoCanvas: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    let asset: PhotoAsset

    @State private var preview: PreviewImage?
    @State private var previewSource: AssetSource?
    @State private var panOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnification = MagnificationState()

    var body: some View {
        GeometryReader { geometry in
            let displayedPreview = previewSource == asset.previewSource
                ? preview
                : PreviewPipeline.shared.cachedImage(for: asset.previewSource)
            let layoutSize = layoutImageSize(preview: displayedPreview)
            let imageRect = aspectFitRect(
                imageSize: layoutSize,
                containerSize: geometry.size,
                inset: 24
            )
            let sourceSize = sourcePixelSize(preview: displayedPreview)
            let metrics = CanvasMetrics(
                imageRect: imageRect,
                sourcePixelSize: sourceSize,
                displayScale: displayScale
            )
            let liveZoom = effectiveZoom
            let livePanOffset = anchoredOffset(
                imageCenter: CGPoint(x: imageRect.midX, y: imageRect.midY),
                containerSize: geometry.size
            )

            ZStack {
                PickroomColors.canvas

                if let displayedPreview {
                    ZStack {
                        Image(decorative: displayedPreview.cgImage, scale: 1, orientation: .up)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: imageRect.width, height: imageRect.height)
                            .pickroomBackgroundExtension()

                        if model.compositionGridEnabled {
                            CompositionGrid()
                                .frame(width: imageRect.width, height: imageRect.height)
                                .allowsHitTesting(false)
                        }
                    }
                        .overlay {
                            Rectangle()
                                .strokeBorder(
                                    .white.opacity(0.16),
                                    lineWidth: 1 / max(displayScale, 1)
                                )
                        }
                        .scaleEffect(liveZoom)
                        .position(x: imageRect.midX, y: imageRect.midY)
                        .offset(
                            x: livePanOffset.width + dragOffset.width,
                            y: livePanOffset.height + dragOffset.height
                        )
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }

                VStack {
                    HStack {
                        PhotoPositionBadge()
                        Spacer()
                        DecisionBadge(decision: asset.decision)
                    }

                    Spacer()

                    if asset.needsOriginalDownload,
                       displayedPreview?.isLocalStandIn == true {
                        CloudOriginalBanner(isZoomedIn: model.zoomScale > 1.001)
                    }
                }
                .padding(18)
            }
            .contentShape(Rectangle())
            .clipped()
            .overlay {
                TrackpadScrollCatcher { sample in
                    scrollPan(
                        sample,
                        imageRect: imageRect,
                        containerSize: geometry.size
                    )
                }
            }
            .gesture(panGesture(imageRect: imageRect, containerSize: geometry.size))
            .simultaneousGesture(
                magnifyGesture(imageRect: imageRect, containerSize: geometry.size)
            )
            .simultaneousGesture(
                doubleClickGesture(imageRect: imageRect, containerSize: geometry.size)
            )
            .onChange(of: metrics, initial: true) { _, newMetrics in
                model.updateFitPixelScale(
                    ZoomMath.fitPixelScale(
                        imageRect: newMetrics.imageRect,
                        sourcePixelSize: newMetrics.sourcePixelSize,
                        displayScale: newMetrics.displayScale
                    )
                )
                panOffset = constrained(
                    panOffset,
                    imageRect: newMetrics.imageRect,
                    containerSize: geometry.size,
                    zoom: model.zoomScale
                )
            }
            .onChange(of: model.zoomScale) { _, newScale in
                if newScale <= 1.001 {
                    panOffset = .zero
                } else {
                    panOffset = constrained(
                        panOffset,
                        imageRect: imageRect,
                        containerSize: geometry.size,
                        zoom: newScale
                    )
                }
            }
            .onChange(of: asset.previewSource, initial: true) { _, newSource in
                model.resolveDetailsIfNeeded(for: asset)
                if let cached = PreviewPipeline.shared.cachedImage(for: newSource) {
                    preview = cached
                    previewSource = newSource
                } else {
                    preview = nil
                    previewSource = nil
                }
            }
            .task(id: previewRequest(containerSize: geometry.size, preview: displayedPreview)) {
                let requestedSize = previewRequestPixelSize(
                    containerSize: geometry.size,
                    preview: displayedPreview
                )
                guard let loaded = await PreviewPipeline.shared.image(
                    for: asset.previewSource,
                    maxPixelSize: requestedSize,
                    priority: .foreground
                ), !Task.isCancelled else {
                    return
                }

                preview = loaded
                previewSource = asset.previewSource
                panOffset = constrained(
                    panOffset,
                    imageRect: imageRect,
                    containerSize: geometry.size,
                    zoom: model.zoomScale
                )

                let neighbors = model.neighboringAssets()
                Task {
                    for neighbor in neighbors {
                        _ = await PreviewPipeline.shared.image(
                            for: neighbor.previewSource,
                            maxPixelSize: 3_200,
                            priority: .background
                        )
                    }
                }
            }
        }
        .accessibilityLabel(asset.filename)
        .accessibilityValue(asset.decision.title)
        .accessibilityHint("Pinch or double-click to inspect focus")
    }

    private var effectiveZoom: CGFloat {
        min(
            max(model.zoomScale * magnification.factor, 1),
            model.maximumZoomScale
        )
    }

    private func anchoredOffset(imageCenter: CGPoint, containerSize: CGSize) -> CGSize {
        guard abs(effectiveZoom - model.zoomScale) > 0.0001 else {
            return panOffset
        }

        let ratio = effectiveZoom / max(model.zoomScale, 0.001)
        let anchor = point(for: magnification.anchor, in: containerSize)
        return ZoomMath.anchoredOffset(
            currentOffset: panOffset,
            imageCenter: imageCenter,
            anchor: anchor,
            scaleRatio: ratio
        )
    }

    private func panGesture(imageRect: CGRect, containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragOffset) { value, state, _ in
                guard model.zoomScale > 1.001 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard model.zoomScale > 1.001 else { return }
                panOffset = constrained(
                    CGSize(
                        width: panOffset.width + value.translation.width,
                        height: panOffset.height + value.translation.height
                    ),
                    imageRect: imageRect,
                    containerSize: containerSize,
                    zoom: model.zoomScale
                )
            }
    }

    /// Pans a zoomed photo with two-finger scrolling, matching the drag gesture.
    private func scrollPan(
        _ sample: ScrollSample,
        imageRect: CGRect,
        containerSize: CGSize
    ) {
        guard model.zoomScale > 1.001 else { return }

        panOffset = constrained(
            CGSize(
                width: panOffset.width + sample.deltaX,
                height: panOffset.height + sample.deltaY
            ),
            imageRect: imageRect,
            containerSize: containerSize,
            zoom: model.zoomScale
        )
    }

    private func magnifyGesture(imageRect: CGRect, containerSize: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .updating($magnification) { value, state, _ in
                state = MagnificationState(
                    factor: value.magnification,
                    anchor: value.startAnchor
                )
            }
            .onEnded { value in
                let oldZoom = model.zoomScale
                let newZoom = min(
                    max(oldZoom * value.magnification, 1),
                    model.maximumZoomScale
                )
                let anchor = point(for: value.startAnchor, in: containerSize)
                let anchored = ZoomMath.anchoredOffset(
                    currentOffset: panOffset,
                    imageCenter: CGPoint(x: imageRect.midX, y: imageRect.midY),
                    anchor: anchor,
                    scaleRatio: newZoom / max(oldZoom, 0.001)
                )
                model.setZoom(newZoom)
                panOffset = constrained(
                    anchored,
                    imageRect: imageRect,
                    containerSize: containerSize,
                    zoom: newZoom
                )
            }
    }

    private func doubleClickGesture(
        imageRect: CGRect,
        containerSize: CGSize
    ) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                if model.zoomScale > 1.001 {
                    model.resetZoom()
                    panOffset = .zero
                    return
                }

                let oldZoom = model.zoomScale
                let newZoom = min(
                    max(1 / max(model.fitPixelScale, 0.001), 1),
                    model.maximumZoomScale
                )
                let anchored = ZoomMath.anchoredOffset(
                    currentOffset: panOffset,
                    imageCenter: CGPoint(x: imageRect.midX, y: imageRect.midY),
                    anchor: value.location,
                    scaleRatio: newZoom / max(oldZoom, 0.001)
                )
                model.setZoom(newZoom)
                panOffset = constrained(
                    anchored,
                    imageRect: imageRect,
                    containerSize: containerSize,
                    zoom: newZoom
                )
            }
    }

    private func point(for anchor: UnitPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: anchor.x * size.width, y: anchor.y * size.height)
    }

    private func layoutImageSize(preview: PreviewImage?) -> CGSize {
        if let preview {
            return CGSize(
                width: preview.cgImage.width,
                height: preview.cgImage.height
            )
        }
        if let width = asset.metadata.pixelWidth,
           let height = asset.metadata.pixelHeight {
            return CGSize(width: width, height: height)
        }
        return CGSize(width: 3, height: 2)
    }

    private func sourcePixelSize(preview: PreviewImage?) -> CGSize {
        if let width = asset.metadata.pixelWidth,
           let height = asset.metadata.pixelHeight {
            return CGSize(width: width, height: height)
        }
        return layoutImageSize(preview: preview)
    }

    private func previewRequest(
        containerSize: CGSize,
        preview: PreviewImage?
    ) -> PreviewRequest {
        PreviewRequest(
            source: asset.previewSource,
            maxPixelSize: previewRequestPixelSize(
                containerSize: containerSize,
                preview: preview
            )
        )
    }

    private func previewRequestPixelSize(
        containerSize: CGSize,
        preview: PreviewImage?
    ) -> Int {
        let layoutSize = layoutImageSize(preview: preview)
        let imageRect = aspectFitRect(
            imageSize: layoutSize,
            containerSize: containerSize,
            inset: 24
        )
        let sourceSize = sourcePixelSize(preview: preview)
        let sourceLongEdge = max(sourceSize.width, sourceSize.height)
        let fitScale = ZoomMath.fitPixelScale(
            imageRect: imageRect,
            sourcePixelSize: sourceSize,
            displayScale: displayScale
        )
        let actualScale = fitScale * model.zoomScale
        let neededLongEdge = sourceLongEdge * min(max(actualScale * 1.12, 0), 1)
        let baseSize = max(3_200, Int(neededLongEdge.rounded(.up)))
        let knownSourceSize = max(Int(sourceLongEdge.rounded()), 3_200)
        return min(baseSize, knownSourceSize)
    }

    private func aspectFitRect(
        imageSize: CGSize,
        containerSize: CGSize,
        inset: CGFloat
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        let available = CGSize(
            width: max(containerSize.width - inset * 2, 1),
            height: max(containerSize.height - inset * 2, 1)
        )
        let scale = min(
            available.width / imageSize.width,
            available.height / imageSize.height
        )
        let fitted = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: (containerSize.width - fitted.width) / 2,
            y: (containerSize.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func constrained(
        _ offset: CGSize,
        imageRect: CGRect,
        containerSize: CGSize,
        zoom: CGFloat
    ) -> CGSize {
        let scaledWidth = imageRect.width * zoom
        let scaledHeight = imageRect.height * zoom
        let maxX = max((scaledWidth - containerSize.width) / 2 + 24, 0)
        let maxY = max((scaledHeight - containerSize.height) / 2 + 24, 0)

        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}

private extension View {
    @ViewBuilder
    func pickroomBackgroundExtension() -> some View {
        if #available(macOS 26.0, *) {
            backgroundExtensionEffect()
        } else {
            self
        }
    }
}

private struct MagnificationState: Equatable {
    var factor: CGFloat = 1
    var anchor: UnitPoint = .center
}

private struct CanvasMetrics: Equatable {
    let imageRect: CGRect
    let sourcePixelSize: CGSize
    let displayScale: CGFloat
}

private struct PreviewRequest: Hashable {
    let source: AssetSource
    let maxPixelSize: Int
}

private struct PhotoPositionBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Text(model.currentAsset?.filename ?? "")
                .lineLimit(1)
                .truncationMode(.middle)

            if let index = model.currentVisibleIndex {
                Text("\(index + 1) / \(model.filteredAssets.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.62), in: Capsule())
    }
}

/// Shown when the frame on screen is the largest copy stored on this Mac.
/// Downloading is always the user's call, never automatic.
private struct CloudOriginalBanner: View {
    @Environment(AppModel.self) private var model

    let isZoomedIn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud")
                .foregroundStyle(.white.opacity(0.85))

            Text(
                isZoomedIn
                    ? "Showing the local preview. The original is still in iCloud."
                    : "Original is in iCloud. Download it to check focus at 1:1."
            )
            .lineLimit(2)

            if model.isDownloadingOriginal {
                ProgressView(value: model.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 84)
            } else {
                Button("Download") {
                    Task { await model.downloadCurrentOriginal() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.68), in: Capsule())
        .transition(.opacity)
    }
}

private struct DecisionBadge: View {
    let decision: PhotoDecision

    var body: some View {
        Label(decision.shortTitle, systemImage: decision.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(decision == .unreviewed ? .white : decision.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.62), in: Capsule())
    }
}

private struct CompositionGrid: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            var path = Path()
            for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                path.move(to: CGPoint(x: size.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                path.move(to: CGPoint(x: 0, y: size.height * fraction))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
            let pixel = 1 / max(displayScale, 1)
            context.stroke(
                path,
                with: .color(.black.opacity(0.16)),
                lineWidth: pixel * 2
            )
            context.stroke(
                path,
                with: .color(.white.opacity(0.32)),
                lineWidth: pixel
            )
        }
    }
}
