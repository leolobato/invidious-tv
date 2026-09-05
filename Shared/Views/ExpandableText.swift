import SwiftUI

/// Text capped at a few lines with a More / Show less toggle.
///
/// The toggle only appears when the text really is longer than the cap: the full text is laid out
/// invisibly at the same width and its height compared with the capped one.
struct ExpandableText: View {
    let text: Text
    var lineLimit: Int = 3
    @Binding var expanded: Bool

    @State private var cappedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool { fullHeight > cappedHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            text
                .lineLimit(expanded ? nil : lineLimit)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if !expanded { cappedHeight = height }
                }
                .background(alignment: .topLeading) {
                    text
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
            if isTruncated || expanded {
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "More")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
