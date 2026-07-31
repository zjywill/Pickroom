import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("Source") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.sourceName)
                            .lineLimit(1)
                        if let folder = model.sourceFolder {
                            Text(folder.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                } icon: {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.tint)
                }

                Button {
                    model.openFolder()
                } label: {
                    Label("Choose Another Folder", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
            }

            Section("Library") {
                ForEach(LibraryFilter.allCases) { filter in
                    FilterRow(
                        filter: filter,
                        count: model.count(for: filter),
                        isSelected: model.filter == filter
                    ) {
                        model.filter = filter
                    }
                }
            }

            if !model.assets.isEmpty {
                Section("Progress") {
                    ProgressView(
                        value: Double(model.assets.count - model.count(for: .unreviewed)),
                        total: Double(model.assets.count)
                    )
                    .tint(Color(red: 0.20, green: 0.78, blue: 0.58))

                    Text("\(model.assets.count - model.count(for: .unreviewed)) of \(model.assets.count) reviewed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Pickroom")
    }
}

private struct FilterRow: View {
    let filter: LibraryFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: filter.symbol)
                    .frame(width: 18)
                    .foregroundStyle(symbolColor)

                Text(filter.title)

                Spacer(minLength: 8)

                Text(count, format: .number)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelected
                ? Color.accentColor.opacity(0.16)
                : Color.clear
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var symbolColor: Color {
        switch filter {
        case .picks: PhotoDecision.pick.tint
        case .maybes: PhotoDecision.maybe.tint
        case .rejects: PhotoDecision.reject.tint
        default: .secondary
        }
    }
}
