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
            #expect(Int(result.size.width) == 750)
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

    @MainActor
    @Test("Nova execução limpa o trabalho e preserva preferências")
    func freshLaunchClearsWorkAndPreservesPreferences() throws {
        try withTemporaryDirectory { directory in
            let persistence = SessionPersistence(
                rootDirectory: directory.appendingPathComponent("sessao")
            )
            try FileManager.default.createDirectory(
                at: persistence.sourcesDirectory,
                withIntermediateDirectories: true
            )
            let sourceURL = try makeImage(
                in: persistence.sourcesDirectory,
                name: "trabalho-anterior",
                width: 640,
                height: 480,
                color: .black
            )
            var previous = CompositionState(
                items: [
                    CompositionItem(
                        sourceURL: sourceURL,
                        originalWidth: 640,
                        originalHeight: 480
                    )
                ],
                layoutMode: .comparison,
                automaticCropMode: .uniformBorders
            )
            previous.outputProfile.preferredWidth = 1200
            previous.outputProfile.outerMargin = 18
            try persistence.save(previous)

            let store = ProjectStore(
                persistence: persistence,
                restoreMonitorPreference: false,
                startEmpty: true
            )

            #expect(store.state.items.isEmpty)
            #expect(store.state.rowGroups.isEmpty)
            #expect(store.state.rowBreaks.isEmpty)
            #expect(store.state.layoutMode == .comparison)
            #expect(store.state.automaticCropMode == .uniformBorders)
            #expect(store.state.outputProfile.preferredWidth == 1200)
            #expect(store.state.outputProfile.outerMargin == 18)
            #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
            #expect(persistence.load()?.items.isEmpty == true)
        }
    }

    @MainActor
    @Test("Editor de legenda usa comandos textuais e inspeção ortográfica")
    func captionEditorUsesTextCommandsAndSpellChecking() {
        let textView = NSTextView()
        let button = NSButton()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        window.makeFirstResponder(textView)

        #expect(TextEditingSupport.isEditingText(textView))
        #expect(!TextEditingSupport.isEditingText(button))
        #expect(!TextEditingSupport.performIfEditing(.copy, responder: button))
        #expect(window.firstResponder === textView)
        TextEditingSupport.endEditing(in: window)
        #expect(window.firstResponder !== textView)
        #expect(!textView.isContinuousSpellCheckingEnabled)

        TextEditingSupport.enableSystemSpelling(on: textView)

        #expect(textView.isContinuousSpellCheckingEnabled)
        #expect(TextEditingAction.copy.selector == #selector(NSText.copy(_:)))
        #expect(TextEditingAction.paste.selector == #selector(NSText.paste(_:)))
        #expect(
            TextEditingShortcut.action(
                keyCode: 8,
                modifiers: .command
            ) == .copy
        )
        #expect(
            TextEditingShortcut.action(
                keyCode: 9,
                modifiers: [.command, .shift]
            ) == nil
        )
    }

    @MainActor
    @Test("Recorte contínuo gera uma única alteração persistida")
    func cropEditingIsCommittedOnce() throws {
        try withTemporaryDirectory { directory in
            let sourceURL = try makeImage(
                in: directory,
                name: "recorte-transitorio",
                width: 640,
                height: 480,
                color: .black
            )
            let item = CompositionItem(
                sourceURL: sourceURL,
                originalWidth: 640,
                originalHeight: 480
            )
            let persistence = SessionPersistence(
                rootDirectory: directory.appendingPathComponent("sessao")
            )
            try persistence.save(CompositionState(items: [item]))
            let store = ProjectStore(
                persistence: persistence,
                restoreMonitorPreference: false
            )
            store.selectItem(item.id, extending: false)

            store.beginSelectedCropEditing()
            store.previewSelectedCrop(NormalizedCrop(top: 0.05))
            store.previewSelectedCrop(NormalizedCrop(top: 0.12))

            #expect(store.state.items[0].crop.top == 0.12)
            #expect(persistence.load()?.items[0].crop.top == 0)

            store.endSelectedCropEditing()

            #expect(persistence.load()?.items[0].crop.top == 0.12)
            #expect(store.canUndo)
            store.undo()
            #expect(store.state.items[0].crop == .zero)
            #expect(!store.canUndo)
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

    @Test("Legendas individuais e de linha aumentam a composição final")
    func captionsAreRenderedBelowImages() throws {
        try withTemporaryDirectory { directory in
            let first = try makeImage(
                in: directory,
                name: "legenda-a",
                width: 800,
                height: 600,
                color: .black
            )
            let second = try makeImage(
                in: directory,
                name: "legenda-b",
                width: 800,
                height: 600,
                color: .darkGray
            )
            var firstItem = CompositionItem(
                sourceURL: first,
                originalWidth: 800,
                originalHeight: 600,
                caption: "Anterior",
                order: 0
            )
            let secondItem = CompositionItem(
                sourceURL: second,
                originalWidth: 800,
                originalHeight: 600,
                caption: "Atual",
                order: 1
            )
            firstItem.isPrimary = false
            let group = CompositionRowGroup(
                itemIDs: [firstItem.id, secondItem.id],
                caption: "Comparação evolutiva"
            )
            let captionedState = CompositionState(
                items: [firstItem, secondItem],
                rowGroups: [group]
            )
            var plainState = captionedState
            plainState.items[0].caption = ""
            plainState.items[1].caption = ""
            plainState.rowGroups[0].caption = ""

            let captioned = try CompositionRenderer().render(state: captionedState)
            let plain = try CompositionRenderer().render(state: plainState)
            let captionHeight = captioned.size.height - plain.size.height

            #expect(captioned.size.height > plain.size.height)
            #expect(captionHeight <= 64)
            #expect(captioned.pngData != plain.pngData)
        }
    }

    @Test("Fonte das legendas depende da composição, não da imagem")
    func captionTypographyIsUniformWithinComposition() {
        let compositionWidth: CGFloat = 750

        #expect(CaptionMetrics.fontSize(canvasWidth: compositionWidth) == 14)
        #expect(CaptionMetrics.bandHeight(canvasWidth: compositionWidth) == 32)
    }

    @Test("Delete e Forward Delete removem imagens sem modificadores")
    func imageDeletionShortcutRecognizesBothMacKeys() {
        #expect(ImageDeletionShortcut.matches(keyCode: 51, modifiers: []))
        #expect(ImageDeletionShortcut.matches(keyCode: 117, modifiers: [.function]))
        #expect(!ImageDeletionShortcut.matches(keyCode: 51, modifiers: [.command]))
        #expect(!ImageDeletionShortcut.matches(keyCode: 36, modifiers: []))
    }

    @Test("Command W fecha somente a aba de composição")
    func compositionTabCloseShortcutMatchesCommandW() {
        #expect(
            CompositionTabCloseShortcut.matches(
                keyCode: 13,
                modifiers: [.command]
            )
        )
        #expect(
            !CompositionTabCloseShortcut.matches(
                keyCode: 13,
                modifiers: [.command, .shift]
            )
        )
        #expect(
            !CompositionTabCloseShortcut.matches(
                keyCode: 13,
                modifiers: []
            )
        )
    }

    @Test("Última aba é sempre substituída por uma aba vazia")
    func lastTabIsAlwaysReplaced() {
        #expect(
            CompositionTabCloseAction.resolve(tabCount: 1)
                == .replaceWithBlankTab
        )
        #expect(
            CompositionTabCloseAction.resolve(tabCount: 2) == .closeTab
        )
    }

    @MainActor
    @Test("Red button delegates closing without destroying the window")
    func compositionCloseButtonUsesCloseInterceptor() {
        var closeCount = 0
        let interceptor = CompositionWindowCloseInterceptor {
            closeCount += 1
        }
        let button = NSButton()

        interceptor.install(on: button)

        #expect(button.target === interceptor)
        #expect(
            button.action
                == #selector(CompositionWindowCloseInterceptor.handleClose(_:))
        )
        interceptor.handleClose(button)
        #expect(closeCount == 1)
    }

    @Test("Sessão anterior sem grupos continua compatível")
    func legacySessionMigration() throws {
        var state = CompositionState()
        state.layoutMode = .grid
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(state)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "rowGroups")
        object.removeValue(forKey: "rowBreaks")
        object.removeValue(forKey: "schemaVersion")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        var restored = try JSONDecoder.project.decode(CompositionState.self, from: legacyData)
        restored.outputProfile.preferredWidth = 1800

        #expect(restored.id == state.id)
        #expect(restored.layoutMode == .grid)
        #expect(restored.rowGroups.isEmpty)
        #expect(restored.rowBreaks.isEmpty)
        #expect(restored.schemaVersion == 1)
        let didMigrate = restored.migrateIfNeeded()
        #expect(didMigrate)
        #expect(restored.schemaVersion == 3)
        #expect(restored.outputProfile.preferredWidth == 750)
        #expect(restored.outputProfile.outerMargin == 12)
        #expect(restored.outputProfile.horizontalSpacing == 12)
        #expect(restored.outputProfile.verticalSpacing == 12)
    }

    @Test("Abas usam sessões locais independentes")
    func compositionTabsUseIndependentPersistence() {
        let primary = SessionPersistence.live(
            compositionID: SessionPersistence.primaryCompositionID
        )
        let secondary = SessionPersistence.live(compositionID: UUID())

        #expect(primary.rootDirectory == SessionPersistence.live().rootDirectory)
        #expect(secondary.rootDirectory != primary.rootDirectory)
        #expect(secondary.rootDirectory.deletingLastPathComponent().lastPathComponent == "Composicoes")
    }

    @MainActor
    @Test("Store agrupa seleção, edita legenda comum e persiste")
    func projectStoreGroupsSelection() throws {
        try withTemporaryDirectory { directory in
            let firstURL = try makeImage(
                in: directory,
                name: "grupo-a",
                width: 640,
                height: 480,
                color: .black
            )
            let secondURL = try makeImage(
                in: directory,
                name: "grupo-b",
                width: 640,
                height: 480,
                color: .darkGray
            )
            let first = CompositionItem(
                sourceURL: firstURL,
                originalWidth: 640,
                originalHeight: 480,
                order: 0
            )
            let second = CompositionItem(
                sourceURL: secondURL,
                originalWidth: 640,
                originalHeight: 480,
                order: 1
            )
            let persistence = SessionPersistence(
                rootDirectory: directory.appendingPathComponent("sessao")
            )
            try persistence.save(CompositionState(items: [first, second]))
            let store = ProjectStore(
                persistence: persistence,
                restoreMonitorPreference: false
            )

            store.selectItem(second.id, extending: false)
            store.setSelectedRowBreak(true)
            #expect(store.state.rowBreaks == [second.id])
            #expect(persistence.load()?.rowBreaks == [second.id])
            store.undo()
            #expect(store.state.rowBreaks.isEmpty)
            store.redo()
            #expect(store.state.rowBreaks == [second.id])
            store.setSelectedRowBreak(false)

            store.selectItem(first.id, extending: false)
            store.selectItem(second.id, extending: true)
            store.createRowGroup()
            store.updateSelectedGroupCaption("Comparação evolutiva")

            #expect(store.state.rowGroups.count == 1)
            #expect(store.state.rowGroups[0].itemIDs == [first.id, second.id])
            #expect(store.state.rowGroups[0].caption == "Comparação evolutiva")
            #expect(persistence.load()?.rowGroups == store.state.rowGroups)

            store.undo()
            #expect(store.state.rowGroups[0].caption.isEmpty)
            store.undo()
            #expect(store.state.rowGroups.isEmpty)
            store.redo()
            store.redo()
            #expect(store.state.rowGroups[0].caption == "Comparação evolutiva")
        }
    }

    @MainActor
    @Test("Monitoramento importa arquivo sobrescrito após nova composição")
    func monitoringSurvivesNewComposition() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkjaldrMonitorTests-\(UUID().uuidString)", isDirectory: true)
        let watchedDirectory = directory.appendingPathComponent("Capturas", isDirectory: true)
        try FileManager.default.createDirectory(
            at: watchedDirectory,
            withIntermediateDirectories: true
        )
        let persistence = SessionPersistence(
            rootDirectory: directory.appendingPathComponent("Sessao", isDirectory: true)
        )
        let store = ProjectStore(
            persistence: persistence,
            restoreMonitorPreference: false
        )
        defer {
            store.stopMonitoring()
            try? FileManager.default.removeItem(at: directory)
        }

        _ = try makeImage(
            in: watchedDirectory,
            name: "captura-reutilizada",
            width: 640,
            height: 480,
            color: .black
        )
        store.startMonitoring(watchedDirectory)
        store.newComposition()
        try await Task.sleep(for: .milliseconds(20))
        _ = try makeImage(
            in: watchedDirectory,
            name: "captura-reutilizada",
            width: 640,
            height: 480,
            color: .darkGray
        )

        try await Task.sleep(for: .seconds(2))

        #expect(store.monitor.isRunning)
        #expect(store.state.items.count == 1)
    }

    @MainActor
    @Test("Gravação suspende e restaura o monitor de imagens")
    func recordingSuspendsImageMonitoring() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SkjaldrMonitorSuspension-\(UUID().uuidString)",
                isDirectory: true
            )
        let watchedDirectory = directory.appendingPathComponent(
            "Capturas",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: watchedDirectory,
            withIntermediateDirectories: true
        )
        let store = ProjectStore(
            persistence: SessionPersistence(
                rootDirectory: directory.appendingPathComponent("Sessao")
            ),
            restoreMonitorPreference: false
        )
        defer {
            store.stopMonitoring()
            try? FileManager.default.removeItem(at: directory)
        }

        store.startMonitoring(watchedDirectory)
        #expect(store.monitor.isRunning)

        store.suspendForVideoRecording()
        #expect(!store.monitor.isRunning)

        store.resumeAfterVideoRecording()
        #expect(store.monitor.isRunning)
        #expect(store.monitor.directory == watchedDirectory)
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
