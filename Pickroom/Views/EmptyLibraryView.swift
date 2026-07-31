import SwiftUI

struct EmptyLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(isDropTargeted ? 0.16 : 0.08))
                    .frame(width: 112, height: 88)

                Image(systemName: "photo.stack")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.tint)
            }

            VStack(spacing: 8) {
                Text("Open a photo folder")
                    .font(.title2.weight(.semibold))

                Text("Photos stay in place until you explicitly move rejects to Trash.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }

            Button {
                model.openFolder()
            } label: {
                Label("Open Photo Folder", systemImage: "folder.badge.plus")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(Color(nsColor: .controlBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            model.loadDroppedURLs(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted in
            withAnimation(.easeOut(duration: 0.12)) {
                isDropTargeted = isTargeted
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .padding(24)
                .allowsHitTesting(false)
        }
    }
}

struct EmptyFilterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: model.filter.symbol)
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(spacing: 5) {
                Text("No \(model.filter.title)")
                    .font(.title3.weight(.semibold))

                Text("There are no photos in this collection.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Show All Photos") {
                model.filter = .all
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
