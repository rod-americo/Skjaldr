import AppKit
import Foundation

struct RenderedComposition {
    let image: NSImage
    let pngData: Data
    let tiffData: Data
    let size: CGSize

    func data(format: OutputFormat, jpegQuality: Double) -> Data? {
        switch format {
        case .png:
            return pngData
        case .jpeg:
            guard let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
            return bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: max(0, min(1, jpegQuality))]
            )
        }
    }
}

enum RenderError: LocalizedError {
    case emptyProject
    case contextCreation
    case encoding

    var errorDescription: String? {
        switch self {
        case .emptyProject:
            return "Adicione ao menos uma imagem antes de compor."
        case .contextCreation:
            return "Não foi possível criar o contexto de renderização."
        case .encoding:
            return "Não foi possível codificar a composição."
        }
    }
}

struct CompositionRenderer {
    let layoutEngine = LayoutEngine()

    func render(state: CompositionState, width overrideWidth: Int? = nil) throws -> RenderedComposition {
        guard !state.items.isEmpty else { throw RenderError.emptyProject }
        let profile = state.outputProfile
        let requestedWidth = overrideWidth ?? profile.preferredWidth
        let width = max(320, min(profile.maximumWidth, requestedWidth))
        let inputs = state.items.sorted(by: { $0.order < $1.order }).map {
            LayoutEngine.Input(
                id: $0.id,
                aspectRatio: $0.croppedAspectRatio,
                isPrimary: $0.isPrimary,
                hasCaption: !$0.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        let groups = state.rowGroups.map {
            LayoutEngine.Group(
                id: $0.id,
                itemIDs: $0.itemIDs,
                hasCaption: !$0.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }

        func calculateLayout(width: Int) -> LayoutResult {
            let renderScale = CGFloat(width) / CGFloat(profile.preferredWidth)
            return layoutEngine.calculate(
                items: inputs,
                mode: state.layoutMode,
                canvasWidth: CGFloat(width),
                margin: CGFloat(profile.outerMargin) * renderScale,
                horizontalSpacing: CGFloat(profile.horizontalSpacing) * renderScale,
                verticalSpacing: CGFloat(profile.verticalSpacing) * renderScale,
                groups: groups,
                itemCaptionHeight: 112 * renderScale,
                groupCaptionHeight: 120 * renderScale
            )
        }

        var layout = calculateLayout(width: width)

        if layout.size.height > CGFloat(profile.maximumHeight) {
            let reduction = CGFloat(profile.maximumHeight) / layout.size.height
            let reducedWidth = max(320, Int(CGFloat(width) * reduction))
            layout = calculateLayout(width: reducedWidth)
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(layout.size.width)),
            pixelsHigh: Int(ceil(layout.size.height)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw RenderError.contextCreation
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setShouldAntialias(true)
        context.cgContext.interpolationQuality = .high
        NSColor(hex: profile.backgroundHex).setFill()
        NSRect(origin: .zero, size: layout.size).fill()

        let itemByID = Dictionary(uniqueKeysWithValues: state.items.map { ($0.id, $0) })
        for placement in layout.placements {
            guard let item = itemByID[placement.itemID],
                  let image = NSImage(contentsOf: item.sourceURL)
            else {
                continue
            }
            draw(image: image, item: item, inTopLeftFrame: placement.frame, canvasHeight: layout.size.height)
            if let captionFrame = placement.captionFrame {
                drawCaption(
                    item.caption,
                    inTopLeftFrame: captionFrame,
                    canvasHeight: layout.size.height,
                    isGroup: false
                )
            }
        }

        let groupByID = Dictionary(uniqueKeysWithValues: state.rowGroups.map { ($0.id, $0) })
        for placement in layout.groupCaptions {
            guard let group = groupByID[placement.groupID] else { continue }
            drawCaption(
                group.caption,
                inTopLeftFrame: placement.frame,
                canvasHeight: layout.size.height,
                isGroup: true
            )
        }

        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]),
              let tiff = bitmap.representation(using: .tiff, properties: [:])
        else {
            throw RenderError.encoding
        }

        let image = NSImage(size: layout.size)
        image.addRepresentation(bitmap)
        return RenderedComposition(image: image, pngData: png, tiffData: tiff, size: layout.size)
    }

    private func draw(
        image: NSImage,
        item: CompositionItem,
        inTopLeftFrame topFrame: CGRect,
        canvasHeight: CGFloat
    ) {
        let destination = CGRect(
            x: topFrame.minX,
            y: canvasHeight - topFrame.maxY,
            width: topFrame.width,
            height: topFrame.height
        )
        let sourceSize = image.size
        let source = CGRect(
            x: sourceSize.width * item.crop.left,
            y: sourceSize.height * item.crop.bottom,
            width: sourceSize.width * (1 - item.crop.left - item.crop.right),
            height: sourceSize.height * (1 - item.crop.top - item.crop.bottom)
        )
        image.draw(
            in: destination,
            from: source,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func drawCaption(
        _ caption: String,
        inTopLeftFrame topFrame: CGRect,
        canvasHeight: CGFloat,
        isGroup: Bool
    ) {
        guard !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let destination = CGRect(
            x: topFrame.minX,
            y: canvasHeight - topFrame.maxY,
            width: topFrame.width,
            height: topFrame.height
        )
        let background = isGroup
            ? NSColor(calibratedWhite: 0.93, alpha: 1)
            : NSColor(calibratedWhite: 0.97, alpha: 1)
        background.setFill()
        destination.fill()
        NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
        let border = NSBezierPath(rect: destination.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let fontSize = max(12, min(isGroup ? 24 : 22, destination.height * 0.20))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: isGroup ? .semibold : .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let text = NSAttributedString(
            string: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            attributes: attributes
        )
        let available = destination.insetBy(dx: 12, dy: 8)
        let measured = text.boundingRect(
            with: available.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = CGRect(
            x: available.minX,
            y: available.midY - min(available.height, measured.height) / 2,
            width: available.width,
            height: min(available.height, measured.height)
        )
        text.draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }
}

extension NSColor {
    convenience init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        let red, green, blue, alpha: UInt64
        switch value.count {
        case 8:
            (red, green, blue, alpha) = (number >> 24, number >> 16 & 0xFF, number >> 8 & 0xFF, number & 0xFF)
        default:
            (red, green, blue, alpha) = (number >> 16, number >> 8 & 0xFF, number & 0xFF, 0xFF)
        }
        self.init(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}
