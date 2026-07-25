import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SkjaldrApp

@Suite("Renderização, pasteboard e persistência", .serialized)
struct RendererClipboardTests {
    @Test("PNG é uma única imagem e não preserva metadados de origem")
    func rendererProducesSinglePNGWithoutSourceMetadata() throws {
        try withTemporaryDirectory { directory in
            let first = try makeImage(
                in: directory,
                name: "horizontal",
                width: 900,
                height: 500,
                color: .black
            )
            let second = try makeImage(
                in: directory,
                name: "vertical",
                width: 500,
                height: 900,
                color: .darkGray
            )
            let state = CompositionState(
                items: [
                    CompositionItem(sourceURL: first, originalWidth: 900, originalHeight: 500, order: 0),
                    CompositionItem(sourceURL: second, originalWidth: 500, originalHeight: 900, order: 1)
                ]
            )

            let result = try CompositionRenderer().render(state: state)
            #expect(Int(result.size.width) == 1800)
            #expect(result.size.height > 0)
            #expect(result.pngData.count > 100)

            let source = CGImageSourceCreateWithData(result.pngData as CFData, nil)!
            #expect(CGImageSourceGetCount(source) == 1)
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            #expect(properties?[kCGImagePropertyGPSDictionary] == nil)
            #expect(properties?[kCGImagePropertyTIFFDictionary] == nil)
        }
    }

    @Test("Pasteboard publica PNG e TIFF sem tipos que prejudiquem editores HTML")
    func pasteboardPublishesPNGNativeTIFFAndTemporaryFile() throws {
        try withTemporaryDirectory { directory in
            let sourceURL = try makeImage(
                in: directory,
                name: "origem",
                width: 640,
                height: 480,
                color: .black
            )
            let state = CompositionState(
                items: [
                    CompositionItem(sourceURL: sourceURL, originalWidth: 640, originalHeight: 480)
                ]
            )
            let result = try CompositionRenderer().render(state: state, width: 900)
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.skjaldr.tests.\(UUID().uuidString)"))
            let manager = ClipboardManager(
                temporaryDirectory: directory.appendingPathComponent("pasteboard"),
                pasteboard: pasteboard
            )

            try manager.copy(result)
            let types = Set(pasteboard.types ?? [])
            #expect(types.contains(.png))
            #expect(types.contains(.tiff))
            #expect(!types.contains(.fileURL))
            #expect(pasteboard.data(forType: .png) != nil)
            #expect(pasteboard.data(forType: .tiff) != nil)
            #expect(NSImage(pasteboard: pasteboard) != nil)
        }
    }

    @Test("Sessão é recuperada sem alteração")
    func sessionRoundTrip() throws {
        try withTemporaryDirectory { directory in
            let persistence = SessionPersistence(rootDirectory: directory.appendingPathComponent("sessao"))
            var state = CompositionState()
            state.layoutMode = .comparison
            state.outputProfile = .highResolution
            try persistence.save(state)
            let restored = persistence.load()
            #expect(restored?.id == state.id)
            #expect(restored?.items == state.items)
            #expect(restored?.layoutMode == state.layoutMode)
            #expect(restored?.outputProfile == state.outputProfile)
        }
    }

    @Test("Recorte conservador detecta borda uniforme")
    func uniformBorderCrop() throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 200,
            pixelsHigh: 120,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 120).fill()
        NSColor.black.setFill()
        NSRect(x: 20, y: 12, width: 160, height: 96).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 200, height: 120))
        image.addRepresentation(bitmap)

        let crop = UniformBorderCropDetector().detect(in: image)
        #expect(crop.left >= 0.09)
        #expect(crop.right >= 0.09)
        #expect(crop.top >= 0.09)
        #expect(crop.bottom >= 0.09)
        #expect(crop.isValid)
    }

    @Test("Renderiza vinte imagens abaixo da meta de um segundo")
    func renderingPerformance() throws {
        try withTemporaryDirectory { directory in
            let sourceURL = try makeImage(
                in: directory,
                name: "desempenho",
                width: 640,
                height: 480,
                color: .darkGray
            )
            let items = (0..<20).map {
                CompositionItem(
                    sourceURL: sourceURL,
                    originalWidth: 640,
                    originalHeight: 480,
                    order: $0
                )
            }
            let state = CompositionState(items: items)
            let clock = ContinuousClock()
            let start = clock.now
            let result = try CompositionRenderer().render(state: state)
            let elapsed = start.duration(to: clock.now)

            #expect(result.pngData.count > 100)
            #expect(elapsed < .seconds(1))
        }
    }

    @Test("Arraste anuncia somente uma URL de arquivo PNG")
    func dragPublishesFileURL() throws {
        try withTemporaryDirectory { directory in
            let pngData = Data([0x89, 0x50, 0x4E, 0x47])
            let drag = try CompositionDragProvider().prepare(
                pngData: pngData,
                temporaryDirectory: directory
            )

            #expect(drag.provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
            #expect(!drag.provider.hasItemConformingToTypeIdentifier(UTType.png.identifier))
            #expect(drag.provider.suggestedName == "composicao.png")
            #expect(try Data(contentsOf: drag.fileURL) == pngData)
        }
    }

    private func withTemporaryDirectory(_ operation: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkjaldrTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(directory)
    }

    private func makeImage(
        in directory: URL,
        name: String,
        width: Int,
        height: Int,
        color: NSColor
    ) throws -> URL {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let url = directory.appendingPathComponent(name).appendingPathExtension("png")
        try data.write(to: url)
        return url
    }
}
