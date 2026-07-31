import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.filter) {
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

                Button {
                    model.openFolder()
                } label: {
                    Label("Choose Folder", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .help(model.sourceFolder?.path ?? "Choose Folder")
            } header: {
                Text("Source")
            }

            Section {
                ForEach(LibraryFilter.allCases) { filter in
                    FilterRow(
                        filter: filter,
                        count: model.count(for: filter)
                    )
                    .tag(filter)
                }
            } header: {
                Text("Library")
            }

            if !model.assets.isEmpty {
                Section {
                    ProgressView(
                        value: Double(model.assets.count - model.count(for: .unreviewed)),
                        total: Double(model.assets.count)
                    )
                    .tint(Color(red: 0.20, green: 0.78, blue: 0.58))

                    Text("\(model.assets.count - model.count(for: .unreviewed)) of \(model.assets.count) reviewed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } header: {
                    Text("Progress")
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
                }
                .disabled(model.rejectedAssetCount == 0 || model.isManagingRejects)
                .help("Move rejected RAW and paired files to Trash after confirmation")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Pickroom")
    }
}

private struct FilterRow: View {
    let filter: LibraryFilter
    let count: Int

    var body: some View {
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

    private var symbolColor: Color {
        switch filter {
        case .picks: PhotoDecision.pick.tint
        case .maybes: PhotoDecision.maybe.tint
        case .rejects: PhotoDecision.reject.tint
        default: .secondary
        }
    }
}
