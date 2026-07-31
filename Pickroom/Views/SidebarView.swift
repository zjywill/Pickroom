import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
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
                .padding(.leading, 8)

                Button {
                    model.openFolder()
                } label: {
                    Label("Choose Folder", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .padding(.leading, 8)
                }
                .help(model.sourceFolder?.path ?? "Choose Folder")
            } header: {
                SidebarSectionTitle("Source")
            }

            Section {
                ForEach(LibraryFilter.allCases) { filter in
                    FilterRow(
                        filter: filter,
                        count: model.count(for: filter),
                        isSelected: model.filter == filter
                    ) {
                        model.filter = filter
                    }
                }
            } header: {
                SidebarSectionTitle("Library")
            }

            if !model.assets.isEmpty {
                Section {
                    ProgressView(
                        value: Double(model.assets.count - model.count(for: .unreviewed)),
                        total: Double(model.assets.count)
                    )
                    .tint(Color(red: 0.20, green: 0.78, blue: 0.58))
                    .padding(.leading, 8)

                    Text("\(model.assets.count - model.count(for: .unreviewed)) of \(model.assets.count) reviewed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.leading, 8)
                } header: {
                    SidebarSectionTitle("Progress")
                }
            }

            Section {
                Button(role: .destructive) {
                    model.requestTrashConfirmation()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "trash")
                            .frame(width: 18)

                        Text("Move to Trash…")
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Spacer(minLength: 0)

                        if model.isManagingRejects {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                }
                .disabled(model.rejectedAssetCount == 0 || model.isManagingRejects)
                .help("Move rejected RAW and paired files to Trash after confirmation")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Pickroom")
    }
}

private struct SidebarSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .padding(.leading, 8)
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
            .padding(.leading, 8)
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
