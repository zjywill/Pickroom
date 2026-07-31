import SwiftUI

struct PhotoCanvas: View {
    @Environment(AppModel.self) private var model
    let asset: PhotoAsset

    @State private var preview: PreviewImage?
    @State private var panOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PickroomColors.canvas

                if let preview {
                    let imageSize = CGSize(
                        width: preview.cgImage.width,
                        height: preview.cgImage.height
                    )
                    let imageRect = aspectFitRect(
                        imageSize: imageSize,
                        containerSize: geometry.size,
                        inset: 24
                    )

                    ZStack {
                        Image(decorative: preview.cgImage, scale: 1, orientation: .up)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: imageRect.width, height: imageRect.height)

                        if model.compositionGridEnabled {
                            CompositionGrid()
                                .frame(width: imageRect.width, height: imageRect.height)
                                .allowsHitTesting(false)
                        }
                    }
                        .scaleEffect(effectiveZoom)
                        .position(x: imageRect.midX, y: imageRect.midY)
                        .offset(displayOffset)
                        .opacity(model.zoomScale <= 1.001 ? dragOpacity : 1)
                        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
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
                }
                .padding(18)

                if let gestureDecision {
                    GestureDecisionOverlay(decision: gestureDecision)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .clipped()
            .gesture(dragGesture(in: geometry.size))
            .simultaneousGesture(magnifyGesture(in: geometry.size))
            .onTapGesture(count: 2) {
                if model.zoomScale > 1.001 {
                    model.resetZoom()
                    panOffset = .zero
                } else {
                    model.setZoom(2)
                }
            }
            .onChange(of: model.zoomScale) { _, newScale in
                if newScale <= 1.001 {
                    panOffset = .zero
                } else if let preview {
                    let imageSize = CGSize(
                        width: preview.cgImage.width,
                        height: preview.cgImage.height
                    )
                    let imageRect = aspectFitRect(
                        imageSize: imageSize,
                        containerSize: geometry.size,
                        inset: 24
                    )
                    panOffset = constrained(
                        panOffset,
                        imageRect: imageRect,
                        containerSize: geometry.size,
                        zoom: newScale
                    )
                }
            }
        }
        .task(id: asset.url) {
            preview = nil
            panOffset = .zero
            preview = await PreviewPipeline.shared.image(for: asset.url, maxPixelSize: 3_200)
        }
        .accessibilityLabel(asset.filename)
        .accessibilityValue("\(asset.decision.title), \(asset.rating) stars")
    }

    private var effectiveZoom: CGFloat {
        min(max(model.zoomScale * magnification, 1), 8)
    }

    private var displayOffset: CGSize {
        if model.zoomScale > 1.001 || magnification > 1.001 {
            return CGSize(
                width: panOffset.width + dragOffset.width,
                height: panOffset.height + dragOffset.height
            )
        }
        return dragOffset
    }

    private func dragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                if model.zoomScale > 1.001, let preview {
                    let imageSize = CGSize(
                        width: preview.cgImage.width,
                        height: preview.cgImage.height
                    )
                    let imageRect = aspectFitRect(
                        imageSize: imageSize,
                        containerSize: containerSize,
                        inset: 24
                    )
                    panOffset = constrained(
                        CGSize(
                            width: panOffset.width + value.translation.width,
                            height: panOffset.height + value.translation.height
                        ),
                        imageRect: imageRect,
                        containerSize: containerSize,
                        zoom: model.zoomScale
                    )
                    return
                }

                let horizontal = value.predictedEndTranslation.width
                let vertical = value.predictedEndTranslation.height

                if abs(vertical) > abs(horizontal), vertical < -120 {
                    model.setDecision(.reject)
                } else if abs(vertical) > abs(horizontal), vertical > 120 {
                    model.setDecision(.pick)
                } else if horizontal < -120 {
                    model.selectNext()
                } else if horizontal > 120 {
                    model.selectPrevious()
                }
            }
    }

    private func magnifyGesture(in containerSize: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .updating($magnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                model.setZoom(model.zoomScale * value.magnification)

                guard let preview else { return }
                let imageSize = CGSize(
                    width: preview.cgImage.width,
                    height: preview.cgImage.height
                )
                let imageRect = aspectFitRect(
                    imageSize: imageSize,
                    containerSize: containerSize,
                    inset: 24
                )
                panOffset = constrained(
                    panOffset,
                    imageRect: imageRect,
                    containerSize: containerSize,
                    zoom: model.zoomScale
                )
            }
    }

    private var dragOpacity: Double {
        let distance = hypot(dragOffset.width, dragOffset.height)
        return max(0.58, 1 - Double(distance / 900))
    }

    private var gestureDecision: PhotoDecision? {
        guard model.zoomScale <= 1.001 else { return nil }
        guard abs(dragOffset.height) > abs(dragOffset.width) else { return nil }
        if dragOffset.height < -36 { return .reject }
        if dragOffset.height > 36 { return .pick }
        return nil
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

private struct GestureDecisionOverlay: View {
    let decision: PhotoDecision

    var body: some View {
        Label(
            decision == .pick ? "Pick" : "Reject",
            systemImage: decision.symbol
        )
        .font(.title2.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(decision.tint.opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

private struct CompositionGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                path.move(to: CGPoint(x: size.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                path.move(to: CGPoint(x: 0, y: size.height * fraction))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
            context.stroke(path, with: .color(.white.opacity(0.72)), lineWidth: 1)
        }
        .overlay {
            Rectangle()
                .strokeBorder(.black.opacity(0.28), lineWidth: 1)
        }
    }
}
