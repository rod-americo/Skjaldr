import AppKit
import Foundation
import UniformTypeIdentifiers

enum ImportError: LocalizedError {
    case unsupportedFormat
    case unreadableImage
    case cannotCreateSessionDirectory

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "O formato do arquivo não é compatível."
        case .unreadableImage:
            return "Não foi possível ler a imagem."
        case .cannotCreateSessionDirectory:
            return "Não foi possível preparar o armazenamento local da sessão."
        }
    }
}

struct ImageImporter {
    let sourcesDirectory: URL

    static let supportedTypes: [UTType] = [
        .png, .jpeg, .tiff, .heic, .webP, .bmp, .image
    ]

    init(sourcesDirectory: URL) {
        self.sourcesDirectory = sourcesDirectory
    }

    func importFile(_ sourceURL: URL, order: Int, automaticCrop: AutomaticCropMode) throws -> CompositionItem {
        try prepareDirectory()
        let values = try sourceURL.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let type = values.contentType,
              type.conforms(to: .image)
        else {
            throw ImportError.unsupportedFormat
        }

        guard let image = NSImage(contentsOf: sourceURL),
              let dimensions = image.pixelDimensions
        else {
            throw ImportError.unreadableImage
        }

        let fileExtension = sourceURL.pathExtension.isEmpty
            ? preferredExtension(for: type)
            : sourceURL.pathExtension.lowercased()
        let destination = sourcesDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        var item = CompositionItem(
            sourceURL: destination,
            originalWidth: dimensions.width,
            originalHeight: dimensions.height,
            order: order
        )
        if automaticCrop == .uniformBorders {
            item.crop = UniformBorderCropDetector().detect(in: image)
        }
        return item
    }

    func importImage(_ image: NSImage, order: Int, automaticCrop: AutomaticCropMode) throws -> CompositionItem {
        try prepareDirectory()
        guard let dimensions = image.pixelDimensions,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw ImportError.unreadableImage
        }

        let destination = sourcesDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: destination, options: .atomic)

        var item = CompositionItem(
            sourceURL: destination,
            originalWidth: dimensions.width,
            originalHeight: dimensions.height,
            order: order
        )
        if automaticCrop == .uniformBorders {
            item.crop = UniformBorderCropDetector().detect(in: image)
        }
        return item
    }

    private func prepareDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: sourcesDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw ImportError.cannotCreateSessionDirectory
        }
    }

    private func preferredExtension(for type: UTType) -> String {
        type.preferredFilenameExtension ?? "png"
    }
}

extension NSImage {
    var pixelDimensions: (width: Int, height: Int)? {
        guard let representation = representations.max(by: {
            $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
        }) else {
            return nil
        }
        return (representation.pixelsWide, representation.pixelsHigh)
    }
}
