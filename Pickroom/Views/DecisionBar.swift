import SwiftUI

struct DecisionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            DecisionButton(
                title: "Reject",
                shortcut: "X",
                symbol: "xmark",
                decision: .reject
            ) {
                model.setDecision(.reject)
            }

            DecisionButton(
                title: "Maybe",
                shortcut: "M",
                symbol: "questionmark",
                decision: .maybe
            ) {
                model.setDecision(.maybe)
            }

            Button {
                model.setDecision(.unreviewed, advance: false)
            } label: {
                Label("Unmark", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Unmark (U)")

            DecisionButton(
                title: "Pick",
                shortcut: "P",
                symbol: "checkmark",
                decision: .pick
            ) {
                model.setDecision(.pick)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct DecisionButton: View {
    let title: String
    let shortcut: String
    let symbol: String
    let decision: PhotoDecision
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .fontWeight(.semibold)
                Text(title)
                    .fontWeight(.semibold)
                Text(shortcut)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
            .frame(minWidth: 112)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(decision.tint)
        .help("\(title) (\(shortcut))")
    }
}
