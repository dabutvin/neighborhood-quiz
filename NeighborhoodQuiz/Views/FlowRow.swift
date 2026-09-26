import SwiftUI

/// A row of pills that wraps onto a second line when it runs out of room, each line
/// centred — rather than squeezing every pill until the names inside them break
/// mid-word, which is what an `HStack` does and what "Manhatta / n" looked like.
///
/// Every child is laid out at its own ideal size and never asked to be narrower. The
/// menu offers up to six choices, five boroughs and Anywhere, and no phone is wide
/// enough for all of them on one line at a size anybody could press.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let available = proposal.width ?? .infinity
        let lines = FlowRow.lines(for: sizes.map(\.width), in: available, spacing: spacing)
        let widest = lines.map { width(of: $0, in: sizes) }.max() ?? 0
        let height = lines.map { tallest(of: $0, in: sizes) }.reduce(0, +)
            + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: available.isFinite ? available : widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let lines = FlowRow.lines(for: sizes.map(\.width), in: bounds.width, spacing: spacing)
        var y = bounds.minY
        for line in lines {
            let height = tallest(of: line, in: sizes)
            var x = bounds.minX + (bounds.width - width(of: line, in: sizes)) / 2
            for index in line {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += height + lineSpacing
        }
    }

    /// Which children go on which line: as many as fit, in order, and a new line when
    /// the next would not. A child wider than the whole row still gets a line to itself
    /// rather than being dropped. Split out from the layout so it can be tested with
    /// plain numbers.
    static func lines(for widths: [CGFloat], in available: CGFloat, spacing: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let needed = current.isEmpty ? width : used + spacing + width
            if needed > available, !current.isEmpty {
                lines.append(current)
                current = [index]
                used = width
            } else {
                current.append(index)
                used = needed
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private func width(of line: [Int], in sizes: [CGSize]) -> CGFloat {
        line.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(line.count - 1, 0))
    }

    private func tallest(of line: [Int], in sizes: [CGSize]) -> CGFloat {
        line.map { sizes[$0].height }.max() ?? 0
    }
}
