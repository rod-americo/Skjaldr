import CoreGraphics
import Foundation

struct LayoutPlacement: Equatable {
    let itemID: UUID
    let frame: CGRect
    let captionFrame: CGRect?
}

struct GroupCaptionPlacement: Equatable {
    let groupID: UUID
    let frame: CGRect
}

struct LayoutResult: Equatable {
    let size: CGSize
    let placements: [LayoutPlacement]
    let groupCaptions: [GroupCaptionPlacement]
}

struct LayoutEngine {
    struct Input {
        let id: UUID
        let aspectRatio: Double
        let isPrimary: Bool
        let hasCaption: Bool

        init(
            id: UUID,
            aspectRatio: Double,
            isPrimary: Bool,
            hasCaption: Bool = false
        ) {
            self.id = id
            self.aspectRatio = aspectRatio
            self.isPrimary = isPrimary
            self.hasCaption = hasCaption
        }
    }

    struct Group {
        let id: UUID
        let itemIDs: [UUID]
        let hasCaption: Bool
    }

    func calculate(
        items: [Input],
        mode: LayoutMode,
        canvasWidth: CGFloat,
        margin: CGFloat,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat,
        groups: [Group] = [],
        itemCaptionHeight: CGFloat = 0,
        groupCaptionHeight: CGFloat = 0
    ) -> LayoutResult {
        guard !items.isEmpty, canvasWidth > margin * 2 else {
            return LayoutResult(
                size: CGSize(width: canvasWidth, height: max(1, margin * 2)),
                placements: [],
                groupCaptions: []
            )
        }

        if !groups.isEmpty {
            return groupedLayout(
                items: items,
                groups: groups,
                mode: mode,
                width: canvasWidth,
                margin: margin,
                hSpacing: horizontalSpacing,
                vSpacing: verticalSpacing,
                itemCaptionHeight: itemCaptionHeight,
                groupCaptionHeight: groupCaptionHeight
            )
        }

        return ungroupedLayout(
            items: items,
            mode: mode,
            canvasWidth: canvasWidth,
            margin: margin,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            itemCaptionHeight: itemCaptionHeight
        )
    }

    private func ungroupedLayout(
        items: [Input],
        mode: LayoutMode,
        canvasWidth: CGFloat,
        margin: CGFloat,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat,
        itemCaptionHeight: CGFloat
    ) -> LayoutResult {
        switch mode {
        case .automatic:
            if let primaryIndex = items.firstIndex(where: \.isPrimary), items.count >= 3 {
                return primaryLayout(
                    items: items,
                    primaryIndex: primaryIndex,
                    width: canvasWidth,
                    margin: margin,
                    hSpacing: horizontalSpacing,
                    vSpacing: verticalSpacing,
                    captionHeight: itemCaptionHeight
                )
            }
            return justifiedLayout(
                items: items,
                width: canvasWidth,
                margin: margin,
                hSpacing: horizontalSpacing,
                vSpacing: verticalSpacing,
                captionHeight: itemCaptionHeight
            )
        case .grid:
            return gridLayout(
                items: items,
                width: canvasWidth,
                margin: margin,
                hSpacing: horizontalSpacing,
                vSpacing: verticalSpacing,
                captionHeight: itemCaptionHeight
            )
        case .comparison:
            return comparisonLayout(
                items: items,
                width: canvasWidth,
                margin: margin,
                hSpacing: horizontalSpacing,
                vSpacing: verticalSpacing,
                captionHeight: itemCaptionHeight
            )
        }
    }

    private func justifiedLayout(
        items: [Input],
        width: CGFloat,
        margin: CGFloat,
        hSpacing: CGFloat,
        vSpacing: CGFloat,
        captionHeight: CGFloat
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
            let hasCaptionBand = captionHeight > 0 && row.contains(where: \.hasCaption)
            let captionTop = ceil(y + rowHeight)

            for item in row {
                let itemWidth = rowHeight * CGFloat(max(0.05, item.aspectRatio))
                let frame = CGRect(x: x, y: y, width: itemWidth, height: rowHeight).integral
                placements.append(
                    LayoutPlacement(
                        itemID: item.id,
                        frame: frame,
                        captionFrame: item.hasCaption && hasCaptionBand
                            ? CGRect(
                                x: frame.minX,
                                y: captionTop,
                                width: frame.width,
                                height: captionHeight
                            ).integral
                            : nil
                    )
                )
                x += itemWidth + hSpacing
            }
            y = captionTop + (hasCaptionBand ? captionHeight : 0) + vSpacing
        }

        let height = max(margin * 2, y - vSpacing + margin)
        return LayoutResult(
            size: CGSize(width: width, height: ceil(height)),
            placements: placements,
            groupCaptions: []
        )
    }

    private func gridLayout(
        items: [Input],
        width: CGFloat,
        margin: CGFloat,
        hSpacing: CGFloat,
        vSpacing: CGFloat,
        captionHeight: CGFloat
    ) -> LayoutResult {
        let columns = max(1, min(3, Int(ceil(sqrt(Double(items.count))))))
        let availableWidth = width - 2 * margin
        let cellWidth = (availableWidth - CGFloat(columns - 1) * hSpacing) / CGFloat(columns)
        let medianRatio = items.map(\.aspectRatio).sorted()[items.count / 2]
        let cellHeight = cellWidth / CGFloat(max(0.65, min(1.8, medianRatio)))
        var placements: [LayoutPlacement] = []
        var y = margin
        let rowCount = Int(ceil(Double(items.count) / Double(columns)))

        for rowIndex in 0..<rowCount {
            let start = rowIndex * columns
            let rowItems = Array(items[start..<min(items.count, start + columns)])
            let hasCaptionBand = captionHeight > 0 && rowItems.contains(where: \.hasCaption)
            let captionTop = ceil(y + cellHeight)
            for (column, item) in rowItems.enumerated() {
                let cell = CGRect(
                    x: margin + CGFloat(column) * (cellWidth + hSpacing),
                    y: y,
                    width: cellWidth,
                    height: cellHeight
                )
                let frame = aspectFit(item.aspectRatio, in: cell).integral
                placements.append(
                    LayoutPlacement(
                        itemID: item.id,
                        frame: frame,
                        captionFrame: item.hasCaption && hasCaptionBand
                            ? CGRect(
                                x: frame.minX,
                                y: captionTop,
                                width: frame.width,
                                height: captionHeight
                            ).integral
                            : nil
                    )
                )
            }
            y = captionTop + (hasCaptionBand ? captionHeight : 0) + vSpacing
        }

        let height = y - vSpacing + margin
        return LayoutResult(
            size: CGSize(width: width, height: ceil(height)),
            placements: placements,
            groupCaptions: []
        )
    }

    private func comparisonLayout(
        items: [Input],
        width: CGFloat,
        margin: CGFloat,
        hSpacing: CGFloat,
        vSpacing: CGFloat,
        captionHeight: CGFloat
    ) -> LayoutResult {
        let availableWidth = width - 2 * margin
        let cellWidth = (availableWidth - hSpacing) / 2
        var placements: [LayoutPlacement] = []
        var y = margin

        for start in stride(from: 0, to: items.count, by: 2) {
            let pair = Array(items[start..<min(items.count, start + 2)])
            let pairHeight = pair.map { cellWidth / CGFloat(max(0.05, $0.aspectRatio)) }.max() ?? cellWidth
            let hasCaptionBand = captionHeight > 0 && pair.contains(where: \.hasCaption)
            let captionTop = ceil(y + pairHeight)
            let pairContentWidth = pair.count == 1 ? cellWidth : availableWidth
            let originX = margin + (availableWidth - pairContentWidth) / 2

            for (offset, item) in pair.enumerated() {
                let cell = CGRect(
                    x: originX + CGFloat(offset) * (cellWidth + hSpacing),
                    y: y,
                    width: cellWidth,
                    height: pairHeight
                )
                let frame = aspectFit(item.aspectRatio, in: cell).integral
                placements.append(
                    LayoutPlacement(
                        itemID: item.id,
                        frame: frame,
                        captionFrame: item.hasCaption && hasCaptionBand
                            ? CGRect(
                                x: frame.minX,
                                y: captionTop,
                                width: frame.width,
                                height: captionHeight
                            ).integral
                            : nil
                    )
                )
            }
            y = captionTop + (hasCaptionBand ? captionHeight : 0) + vSpacing
        }

        return LayoutResult(
            size: CGSize(width: width, height: ceil(y - vSpacing + margin)),
            placements: placements,
            groupCaptions: []
        )
    }

    private func primaryLayout(
        items: [Input],
        primaryIndex: Int,
        width: CGFloat,
        margin: CGFloat,
        hSpacing: CGFloat,
        vSpacing: CGFloat,
        captionHeight: CGFloat
    ) -> LayoutResult {
        let primary = items[primaryIndex]
        let secondary = items.enumerated().filter { $0.offset != primaryIndex }.map(\.element)
        let availableWidth = width - 2 * margin
        let primaryWidth = availableWidth * 0.66
        let sideWidth = availableWidth - primaryWidth - hSpacing
        let primaryHeight = primaryWidth / CGFloat(max(0.05, primary.aspectRatio))
        let primaryCaptionHeight = primary.hasCaption ? captionHeight : 0
        let sideSpacing = vSpacing * CGFloat(max(0, secondary.count - 1))
        let sideCaptionHeight = secondary.reduce(CGFloat.zero) {
            $0 + ($1.hasCaption ? captionHeight : 0)
        }
        let sideHeight = max(
            100,
            (primaryHeight + primaryCaptionHeight - sideSpacing - sideCaptionHeight)
                / CGFloat(secondary.count)
        )

        let primaryFrame = CGRect(
            x: margin,
            y: margin,
            width: primaryWidth,
            height: primaryHeight
        ).integral
        var placements = [
            LayoutPlacement(
                itemID: primary.id,
                frame: primaryFrame,
                captionFrame: primary.hasCaption
                    ? CGRect(
                        x: margin,
                        y: primaryFrame.maxY,
                        width: primaryWidth,
                        height: captionHeight
                    ).integral
                    : nil
            )
        ]
        var sideY = margin
        for item in secondary {
            let cell = CGRect(x: margin + primaryWidth + hSpacing, y: sideY, width: sideWidth, height: sideHeight)
            let frame = aspectFit(item.aspectRatio, in: cell).integral
            let captionTop = ceil(sideY + sideHeight)
            placements.append(
                LayoutPlacement(
                    itemID: item.id,
                    frame: frame,
                    captionFrame: item.hasCaption
                        ? CGRect(
                            x: frame.minX,
                            y: captionTop,
                            width: frame.width,
                            height: captionHeight
                        ).integral
                        : nil
                )
            )
            sideY = captionTop + (item.hasCaption ? captionHeight : 0) + vSpacing
        }
        let primaryBlockHeight = primaryFrame.maxY - margin + primaryCaptionHeight
        let sideBlockHeight = sideY - vSpacing - margin
        let height = max(primaryBlockHeight, sideBlockHeight) + 2 * margin
        return LayoutResult(
            size: CGSize(width: width, height: ceil(height)),
            placements: placements,
            groupCaptions: []
        )
    }

    private func groupedLayout(
        items: [Input],
        groups: [Group],
        mode: LayoutMode,
        width: CGFloat,
        margin: CGFloat,
        hSpacing: CGFloat,
        vSpacing: CGFloat,
        itemCaptionHeight: CGFloat,
        groupCaptionHeight: CGFloat
    ) -> LayoutResult {
        let contentWidth = width - 2 * margin
        let groupByItemID = groups.reduce(into: [UUID: Group]()) { result, group in
            for itemID in group.itemIDs {
                result[itemID] = group
            }
        }
        let inputByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var processedGroups = Set<UUID>()
        var ungroupedBuffer: [Input] = []
        var placements: [LayoutPlacement] = []
        var groupCaptions: [GroupCaptionPlacement] = []
        var y = margin

        func offset(_ result: LayoutResult, by origin: CGPoint) -> LayoutResult {
            LayoutResult(
                size: result.size,
                placements: result.placements.map { placement in
                    LayoutPlacement(
                        itemID: placement.itemID,
                        frame: placement.frame.offsetBy(dx: origin.x, dy: origin.y),
                        captionFrame: placement.captionFrame?.offsetBy(dx: origin.x, dy: origin.y)
                    )
                },
                groupCaptions: result.groupCaptions.map { placement in
                    GroupCaptionPlacement(
                        groupID: placement.groupID,
                        frame: placement.frame.offsetBy(dx: origin.x, dy: origin.y)
                    )
                }
            )
        }

        func append(_ result: LayoutResult) {
            let shifted = offset(result, by: CGPoint(x: margin, y: y))
            placements.append(contentsOf: shifted.placements)
            groupCaptions.append(contentsOf: shifted.groupCaptions)
            y += result.size.height + vSpacing
        }

        func flushUngrouped() {
            guard !ungroupedBuffer.isEmpty else { return }
            append(
                ungroupedLayout(
                    items: ungroupedBuffer,
                    mode: mode,
                    canvasWidth: contentWidth,
                    margin: 0,
                    horizontalSpacing: hSpacing,
                    verticalSpacing: vSpacing,
                    itemCaptionHeight: itemCaptionHeight
                )
            )
            ungroupedBuffer.removeAll()
        }

        for item in items {
            guard let group = groupByItemID[item.id] else {
                ungroupedBuffer.append(item)
                continue
            }
            guard !processedGroups.contains(group.id) else { continue }
            flushUngrouped()
            let groupedItems = group.itemIDs.compactMap { inputByID[$0] }
            if groupedItems.count >= 2 {
                append(
                    forcedGroupRow(
                        items: groupedItems,
                        group: group,
                        width: contentWidth,
                        hSpacing: hSpacing,
                        itemCaptionHeight: itemCaptionHeight,
                        groupCaptionHeight: groupCaptionHeight
                    )
                )
            } else {
                ungroupedBuffer.append(contentsOf: groupedItems)
            }
            processedGroups.insert(group.id)
        }
        flushUngrouped()

        let height = max(margin * 2, y - vSpacing + margin)
        return LayoutResult(
            size: CGSize(width: width, height: ceil(height)),
            placements: placements,
            groupCaptions: groupCaptions
        )
    }

    private func forcedGroupRow(
        items: [Input],
        group: Group,
        width: CGFloat,
        hSpacing: CGFloat,
        itemCaptionHeight: CGFloat,
        groupCaptionHeight: CGFloat
    ) -> LayoutResult {
        let spacing = hSpacing * CGFloat(max(0, items.count - 1))
        let ratioSum = items.reduce(CGFloat.zero) {
            $0 + CGFloat(max(0.05, $1.aspectRatio))
        }
        let rowHeight = max(1, (width - spacing) / ratioSum)
        let captionTop = ceil(rowHeight)
        let hasItemCaptionBand = itemCaptionHeight > 0 && items.contains(where: \.hasCaption)
        let hasGroupCaption = group.hasCaption && groupCaptionHeight > 0
        var x: CGFloat = 0
        var placements: [LayoutPlacement] = []

        for item in items {
            let itemWidth = rowHeight * CGFloat(max(0.05, item.aspectRatio))
            let frame = CGRect(x: x, y: 0, width: itemWidth, height: rowHeight).integral
            placements.append(
                LayoutPlacement(
                    itemID: item.id,
                    frame: frame,
                    captionFrame: item.hasCaption && hasItemCaptionBand
                        ? CGRect(
                            x: frame.minX,
                            y: captionTop,
                            width: frame.width,
                            height: itemCaptionHeight
                        ).integral
                        : nil
                )
            )
            x += itemWidth + hSpacing
        }

        let groupY = captionTop + (hasItemCaptionBand ? itemCaptionHeight : 0)
        let captions = hasGroupCaption
            ? [
                GroupCaptionPlacement(
                    groupID: group.id,
                    frame: CGRect(x: 0, y: groupY, width: width, height: groupCaptionHeight).integral
                )
            ]
            : []
        let height = groupY + (hasGroupCaption ? groupCaptionHeight : 0)
        return LayoutResult(
            size: CGSize(width: width, height: ceil(height)),
            placements: placements,
            groupCaptions: captions
        )
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
