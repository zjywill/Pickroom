import SwiftUI

/// What Pickroom is built on, and under which licence.
///
/// This is not decoration. LibRaw asks for attribution, the CDDL asks that its
/// notices travel with the binary, and someone who only ever saw the DMG has
/// no repository to read — so the licence texts are bundled and shown here.
struct AcknowledgementsView: View {
    private enum Document: String, CaseIterable, Identifiable {
        case cddl = "LibRaw-CDDL-1.0"
        case lgpl = "LibRaw-LGPL-2.1"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .cddl: "CDDL 1.0"
            case .lgpl: "LGPL 2.1"
            }
        }
    }

    @State private var document: Document = .cddl

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("LibRaw 0.22.2")
                    .font(.title3.weight(.semibold))

                Text(
                    "RAW decoding in Pickroom is LibRaw, copyright © 2008–2021 "
                        + "LibRaw LLC, with DHT and AAHD demosaic copyright © 2013 "
                        + "Anton Petrusevich."
                )

                Text(
                    "LibRaw is dual licensed under the LGPL 2.1 and the CDDL 1.0, "
                        + "and Pickroom uses it under the CDDL 1.0. The build it "
                        + "links is unmodified upstream source."
                )

                Link(
                    "libraw.org",
                    destination: URL(string: "https://www.libraw.org")!
                )
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)

            Divider()

            Picker("Licence", selection: $document) {
                ForEach(Document.allCases) { document in
                    Text(document.title).tag(document)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                Text(text(of: document))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .frame(width: 620, height: 620)
    }

    private func text(of document: Document) -> String {
        guard
            let url = Bundle.main.url(forResource: document.rawValue, withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            // The window is the licence notice; an empty pane would read as
            // though there were nothing to notice.
            return "The \(document.title) text is missing from this build. "
                + "It is available at https://www.libraw.org."
        }
        return text
    }
}
