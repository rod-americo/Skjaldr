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
        let scale = CGFloat(width) / CGFloat(profile.preferredWidth)
        let inputs = state.items.sorted(by: { $0.order < $1.order }).map {
            LayoutEngine.Input(id: $0.id, aspectRatio: $0.croppedAspectRatio, isPrimary: $0.isPrimary)
        }
        var layout = layoutEngine.calculate(
            items: inputs,
            mode: state.layoutMode,
            canvasWidth: CGFloat(width),
            margin: CGFloat(profile.outerMargin) * scale,
            horizontalSpacing: CGFloat(profile.horizontalSpacing) * scale,
            verticalSpacing: CGFloat(profile.verticalSpacing) * scale
        )

        if layout.size.height > CGFloat(profile.maximumHeight) {
            let reduction = CGFloat(profile.maximumHeight) / layout.size.height
            let reducedWidth = max(320, Int(CGFloat(width) * reduction))
            layout = layoutEngine.calculate(
                items: inputs,
                mode: state.layoutMode,
                canvasWidth: CGFloat(reducedWidth),
                margin: CGFloat(profile.outerMargin) * reduction,
                horizontalSpacing: CGFloat(profile.horizontalSpacing) * reduction,
                verticalSpacing: CGFloat(profile.verticalSpacing) * reduction
            )
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

        guard !item.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let fontSize = max(13, min(28, destination.height * 0.055))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.68)
        ]
        let text = NSAttributedString(string: " \(item.caption) ", attributes: attributes)
        let size = text.size()
        text.draw(at: CGPoint(x: destination.minX + 8, y: destination.maxY - size.height - 8))
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
