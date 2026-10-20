import SwiftUI

// Buttons wrap onto new rows; rows are centered.
struct FlowLayout: Layout {
  var spacing: CGFloat = 10

  struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  // Button sizes are measured once per content change.
  func makeCache(subviews: Subviews) -> [CGSize] {
    subviews.map { $0.sizeThatFits(.unspecified) }
  }

  func updateCache(_ cache: inout [CGSize], subviews: Subviews) {
    cache = makeCache(subviews: subviews)
  }

  func rows(_ maxWidth: CGFloat, _ sizes: [CGSize]) -> [Row] {
    var rows: [Row] = []
    var row = Row()
    for (index, size) in sizes.enumerated() {
      let width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      if width > maxWidth && !row.indices.isEmpty {
        rows.append(row)
        row = Row(indices: [index], width: size.width, height: size.height)
      } else {
        row.indices.append(index)
        row.width = width
        row.height = max(row.height, size.height)
      }
    }
    if !row.indices.isEmpty { rows.append(row) }
    return rows
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize {
    let rows = rows(proposal.width ?? .infinity, cache)
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) {
    var y = bounds.minY
    for row in rows(bounds.width, cache) {
      var x = bounds.minX + (bounds.width - row.width) / 2
      for index in row.indices {
        let size = cache[index]
        subviews[index].place(
          at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }
}
