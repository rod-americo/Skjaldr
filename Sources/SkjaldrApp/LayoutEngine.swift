import CoreGraphics
import Foundation

struct LayoutPlacement: Equatable {
    let itemID: UUID
    let frame: CGRect
}

struct LayoutResult: Equatable {
    let size: CGSize
    let placements: [LayoutPlacement]
}

struct LayoutEngine {
    struct Input {
        let id: UUID
        let aspectRatio: Double
        let isPrimary: Bool
    }

    func calculate(
        items: [Input],
        mode: LayoutMode,
        canvasWidth: CGFloat,
        margin: CGFloat,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    ) -> LayoutResult {
        guard !items.isEmpty, canvasWidth > margin * 2 else {
            return LayoutResult(size: CGSize(width: canvasWidth, height: max(1, margin * 2)), placements: [])
        }

        switch mode {
        case .automatic:
            if let primaryIndex = items.firstIndex(where: \.isPrimary), items.count >= 3 {
                return primaryLayout(
                    items: items,
                    primaryIndex: primaryIndex,
                    width: canvasWidth,
                    margin: margin,
                    hSpacing: horizontalSpacing,
                    vSpacing: verticalSpacing
                )
            }
            return justifiedLayout(
                items: items,
                width: canvasWidth,
                margin: margin,
                hSpacing: horizontalSpacing,
                vSpacing: verticalSpacing
            )
        case .grid:
            return gridLayout(
                items: items,
                width: canvasWidth,
                margin: margin,
                hSpacing: horizontalSpacing,
                vSpacing: verticalSpacing
            )
        case .comparison:
            return comparisonLayout(
                items: items,
                width: canvasWidth,
                margin: margin,
                hSpacing: horizontalSpacing,
                vSpacing: verticalSpacing
            )
        }
    }

    private func justifiedLayout(
        items: [Input],
        width: CGFloat,
        margin: CGFloat,
        hSpacing: CGFloat,
        vSpacing: CGFloat
    ) -> LayoutResult {
        let availableWidth = width - 2 * margin
        let targetHeight = min(520, max(220, availableWidth / 3))
        let count = items.count
        var costs = Array(repeating: CGFloat.greatestFiniteMagnitude, count: count + 1)
        var breaks = Array(repeating: 0, count: count + 1)
        costs[0] = 0

        for end in 1...count {
            let earliest = max(0, end - 4)
            for start in earliest..<end {
                let row = Array(items[start..<end])
                let ratios = row.reduce(CGFloat.zero) { $0 + CGFloat(max(0.05, $1.aspectRatio)) }
                let spacing = hSpacing * CGFloat(max(0, row.count - 1))
                let rowHeight = (availableWidth - spacing) / ratios
                let heightPenalty = pow((rowHeight - targetHeight) / targetHeight, 2)
                let singletonPenalty: CGFloat = row.count == 1 && count > 1 ? 0.18 : 0
                let excessiveHeightPenalty: CGFloat = rowHeight > availableWidth * 0.9 ? 2 : 0
                let cost = costs[start] + heightPenalty + singletonPenalty + excessiveHeightPenalty
                if cost < costs[end] {
                    costs[end] = cost
                    breaks[end] = start
                }
            }
        }

        var rows: [Range<Int>] = []
        var cursor = count
        while cursor > 0 {
            let start = breaks[cursor]
            rows.append(start..<cursor)
            cursor = start
        }
        rows.reverse()

        var placements: [LayoutPlacement] = []
        var y = margin
        for (rowIndex, range) in rows.enumerated() {
            let row = Array(items[range])
            let ratioSum = row.reduce(CGFloat.zero) { $0 + CGFloat(max(0.05, $1.aspectRatio)) }
            let spacing = hSpacing * CGFloat(max(0, row.count - 1))
            var rowHeight = (availableWidth - spacing) / ratioSum

            // A última linha muito curta mantém escala coerente e fica centralizada.
            let isLast = rowIndex == rows.count - 1
            if isLast && row.count < 3 {
                rowHeight = min(rowHeight, targetHeight)
            }
            let contentWidth = rowHeight * ratioSum + spacing
            var x = margin + max(0, (availableWidth - contentWidth) / 2)

            for item in row {
                let itemWidth = rowHeight * CGFloat(max(0.05, item.aspectRatio))
                placements.append(
                    LayoutPlacement(
                        itemID: item.id,
                        frame: CGRect(x: x, y: y, width: itemWidth, height: rowHeight).integral
                    )
                )
                x += itemWidth + hSpacing
            }
            y += rowHeight + vSpacing
        }

        let height = max(margin * 2, y - vSpacing + margin)
        return LayoutResult(size: CGSize(width: width, height: ceil(height)), placements: placements)
    }

    private func gridLayout(
        items: [Input],
        width: CGFloat,
        margin: CGFloat,
        hSpacing: CGFloat,
        vSpacing: CGFloat
    ) -> LayoutResult {
        let columns = max(1, min(3, Int(ceil(sqrt(Double(items.count))))))
        let availableWidth = width - 2 * margin
        let cellWidth = (availableWidth - CGFloat(columns - 1) * hSpacing) / CGFloat(columns)
        let medianRatio = items.map(\.aspectRatio).sorted()[items.count / 2]
        let cellHeight = cellWidth / CGFloat(max(0.65, min(1.8, medianRatio)))
        var placements: [LayoutPlacement] = []

        for (index, item) in items.enumerated() {
            let row = index / columns
            let column = index % columns
            let cell = CGRect(
                x: margin + CGFloat(column) * (cellWidth + hSpacing),
                y: margin + CGFloat(row) * (cellHeight + vSpacing),
                width: cellWidth,
                height: cellHeight
            )
            placements.append(LayoutPlacement(itemID: item.id, frame: aspectFit(item.aspectRatio, in: cell).integral))
        }

        let rows = Int(ceil(Double(items.count) / Double(columns)))
        let height = 2 * margin + CGFloat(rows) * cellHeight + CGFloat(max(0, rows - 1)) * vSpacing
        return LayoutResult(size: CGSize(width: width, height: ceil(height)), placements: placements)
    }

    private func comparisonLayout(
        items: [Input],
        width: CGFloat,
        margin: CGFloat,
        hSpacing: CGFloat,
        vSpacing: CGFloat
    ) -> LayoutResult {
        let availableWidth = width - 2 * margin
        let cellWidth = (availableWidth - hSpacing) / 2
        var placements: [LayoutPlacement] = []
        var y = margin

        for start in stride(from: 0, to: items.count, by: 2) {
            let pair = Array(items[start..<min(items.count, start + 2)])
            let pairHeight = pair.map { cellWidth / CGFloat(max(0.05, $0.aspectRatio)) }.max() ?? cellWidth
            let pairContentWidth = pair.count == 1 ? cellWidth : availableWidth
            let originX = margin + (availableWidth - pairContentWidth) / 2

            for (offset, item) in pair.enumerated() {
                let cell = CGRect(
                    x: originX + CGFloat(offset) * (cellWidth + hSpacing),
                    y: y,
                    width: cellWidth,
                    height: pairHeight
                )
                placements.append(LayoutPlacement(itemID: item.id, frame: aspectFit(item.aspectRatio, in: cell).integral))
            }
            y += pairHeight + vSpacing
        }

        return LayoutResult(size: CGSize(width: width, height: ceil(y - vSpacing + margin)), placements: placements)
    }

    private func primaryLayout(
        items: [Input],
        primaryIndex: Int,
        width: CGFloat,
        margin: CGFloat,
        hSpacing: CGFloat,
        vSpacing: CGFloat
    ) -> LayoutResult {
        let primary = items[primaryIndex]
        let secondary = items.enumerated().filter { $0.offset != primaryIndex }.map(\.element)
        let availableWidth = width - 2 * margin
        let primaryWidth = availableWidth * 0.66
        let sideWidth = availableWidth - primaryWidth - hSpacing
        let primaryHeight = primaryWidth / CGFloat(max(0.05, primary.aspectRatio))
        let sideSpacing = vSpacing * CGFloat(max(0, secondary.count - 1))
        let sideHeight = max(100, (primaryHeight - sideSpacing) / CGFloat(secondary.count))

        var placements = [
            LayoutPlacement(
                itemID: primary.id,
                frame: CGRect(x: margin, y: margin, width: primaryWidth, height: primaryHeight).integral
            )
        ]
        var sideY = margin
        for item in secondary {
            let cell = CGRect(x: margin + primaryWidth + hSpacing, y: sideY, width: sideWidth, height: sideHeight)
            placements.append(LayoutPlacement(itemID: item.id, frame: aspectFit(item.aspectRatio, in: cell).integral))
            sideY += sideHeight + vSpacing
        }
        let height = max(primaryHeight, sideY - vSpacing - margin) + 2 * margin
        return LayoutResult(size: CGSize(width: width, height: ceil(height)), placements: placements)
    }

    private func aspectFit(_ aspectRatio: Double, in rect: CGRect) -> CGRect {
        let ratio = CGFloat(max(0.05, aspectRatio))
        let rectRatio = rect.width / rect.height
        if ratio > rectRatio {
            let height = rect.width / ratio
            return CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        }
        let width = rect.height * ratio
        return CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
    }
}
