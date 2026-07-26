import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var state: CompositionState
    @Published var selectedItemID: UUID?
    @Published private(set) var selectedItemIDs = Set<UUID>()
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var previewDimensions = CGSize.zero
    @Published private(set) var approximateFileSize = 0
    @Published var toastMessage: String?
    @Published var lastErrorMessage: String?

    let monitor = ScreenshotMonitor()
    private let persistence: SessionPersistence
    private let importer: ImageImporter
    private let renderer = CompositionRenderer()
    private let clipboard: ClipboardManager
    private var undoStates: [CompositionState] = []
    private var redoStates: [CompositionState] = []
    private var toastTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var suspendedMonitoringDirectory: URL?
    private var isSuspendedForRecording = false

    init(
        persistence: SessionPersistence = .live(),
        restoreMonitorPreference: Bool = true
    ) {
        self.persistence = persistence
        self.importer = ImageImporter(sourcesDirectory: persistence.sourcesDirectory)
        self.clipboard = ClipboardManager(temporaryDirectory: persistence.temporaryDirectory)
        var restoredState = persistence.load() ?? CompositionState()
        let migrated = restoredState.migrateIfNeeded()
        self.state = restoredState
        state.items.removeAll { !FileManager.default.fileExists(atPath: $0.sourceURL.path) }
        state.normalizeOrder()
        if migrated {
            try? persistence.save(state)
        }
        refreshPreview()

        if restoreMonitorPreference,
           UserDefaults.standard.bool(forKey: "monitoramentoAtivo"),
           let path = UserDefaults.standard.string(forKey: "pastaMonitorada") {
            startMonitoring(URL(fileURLWithPath: path))
        }
    }

    var selectedItem: CompositionItem? {
        guard let selectedItemID else { return nil }
        return state.items.first(where: { $0.id == selectedItemID })
    }

    var selectedGroup: CompositionRowGroup? {
        guard let selectedItemID else { return nil }
        return state.rowGroups.first(where: { $0.itemIDs.contains(selectedItemID) })
    }

    var canCreateRowGroup: Bool {
        (2...4).contains(selectedItemIDs.count)
    }

    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }

    func openImporter() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ImageImporter.supportedTypes
        panel.message = "Selecione as imagens que farão parte da composição."
        if panel.runModal() == .OK {
            importFiles(panel.urls)
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var next = state
        var imported: [CompositionItem] = []
        var failures = 0
        for url in urls {
            do {
                let item = try importer.importFile(
                    url,
                    order: next.items.count + imported.count,
                    automaticCrop: next.automaticCropMode
                )
                imported.append(item)
            } catch {
                failures += 1
            }
        }
        guard !imported.isEmpty else {
            showError("Nenhuma imagem pôde ser importada.")
            return
        }
        next.items.append(contentsOf: imported)
        next.normalizeOrder()
        commit(next)
        selectedItemID = imported.last?.id
        selectedItemIDs = Set(imported.map(\.id))
        if failures > 0 {
            showToast("\(failures) arquivo(s) ignorado(s)")
        }
    }

    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL], !urls.isEmpty {
            importFiles(urls)
            return
        }
        guard let image = NSImage(pasteboard: pasteboard) else {
            showError("A área de transferência não contém uma imagem compatível.")
            return
        }
        do {
            try importImage(image)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func importDroppedImage(_ image: NSImage) {
        do {
            try importImage(image)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func copyComposition() {
        do {
            let result = try renderer.render(state: state)
            try clipboard.copy(result)
            showToast("Imagem copiada")
        } catch {
            showError(error.localizedDescription)
        }
    }

    func saveComposition() {
        do {
            let result = try renderer.render(state: state)
            let panel = NSSavePanel()
            panel.allowedContentTypes = state.outputProfile.format == .png ? [.png] : [.jpeg]
            panel.nameFieldStringValue = state.outputProfile.format == .png
                ? "composicao.png"
                : "composicao.jpg"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            guard let data = result.data(
                format: state.outputProfile.format,
                jpegQuality: state.outputProfile.jpegQuality
            ) else {
                throw RenderError.encoding
            }
            try data.write(to: url, options: .atomic)
            showToast("Imagem salva")
        } catch {
            showError(error.localizedDescription)
        }
    }

    func shareComposition() {
        do {
            let result = try renderer.render(state: state)
            let url = persistence.temporaryDirectory
                .appendingPathComponent("composicao-compartilhada.png")
            try FileManager.default.createDirectory(
                at: persistence.temporaryDirectory,
                withIntermediateDirectories: true
            )
            try result.pngData.write(to: url, options: .atomic)
            let picker = NSSharingServicePicker(items: [url])
            if let window = NSApp.keyWindow, let view = window.contentView {
                picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func dragProvider() -> NSItemProvider {
        do {
            let result = try renderer.render(state: state)
            return try CompositionDragProvider()
                .prepare(
                    pngData: result.pngData,
                    temporaryDirectory: persistence.temporaryDirectory
                )
                .provider
        } catch {
            let provider = NSItemProvider()
            provider.suggestedName = "composicao-indisponivel.png"
            return provider
        }
    }

    func removeSelected() {
        let ids = selectedItemIDs.isEmpty
            ? Set(selectedItemID.map { [$0] } ?? [])
            : selectedItemIDs
        guard !ids.isEmpty else { return }
        var next = state
        next.items.removeAll { ids.contains($0.id) }
        for index in next.rowGroups.indices {
            next.rowGroups[index].itemIDs.removeAll { ids.contains($0) }
        }
        next.normalizeOrder()
        commit(next)
        selectedItemID = next.items.first?.id
        selectedItemIDs = Set(selectedItemID.map { [$0] } ?? [])
    }

    func duplicateSelected() {
        guard var item = selectedItem else { return }
        var next = state
        item.id = UUID()
        item.order = next.items.count
        item.isPrimary = false
        next.items.append(item)
        next.normalizeOrder()
        commit(next)
        selectedItemID = item.id
        selectedItemIDs = [item.id]
    }

    func moveItem(id: UUID, before targetID: UUID) {
        guard id != targetID else { return }
        var next = state
        let movingIDs = Set(
            next.rowGroups.first(where: { $0.itemIDs.contains(id) })?.itemIDs ?? [id]
        )
        guard !movingIDs.contains(targetID) else { return }
        let movingItems = next.items.filter { movingIDs.contains($0.id) }
        guard !movingItems.isEmpty else { return }
        next.items.removeAll { movingIDs.contains($0.id) }

        let targetGroupIDs = Set(
            next.rowGroups.first(where: { $0.itemIDs.contains(targetID) })?.itemIDs ?? [targetID]
        )
        let targetIndex = next.items.firstIndex(where: { targetGroupIDs.contains($0.id) })
            ?? next.items.endIndex
        next.items.insert(contentsOf: movingItems, at: targetIndex)
        next.normalizeOrder()
        commit(next)
    }

    func selectItem(_ id: UUID, extending: Bool) {
        guard state.items.contains(where: { $0.id == id }) else { return }
        selectedItemID = id
        if extending {
            if selectedItemIDs.contains(id) {
                selectedItemIDs.remove(id)
                selectedItemID = selectedItemIDs.first
            } else {
                selectedItemIDs.insert(id)
            }
        } else {
            selectedItemIDs = [id]
        }
    }

    func createRowGroup() {
        guard canCreateRowGroup else {
            showError("Selecione de duas a quatro imagens com ⌘-clique.")
            return
        }
        var next = state
        let selected = selectedItemIDs
        let orderedIDs = next.items
            .filter { selected.contains($0.id) }
            .sorted(by: { $0.order < $1.order })
            .map(\.id)
        guard let insertionIndex = next.items.firstIndex(where: { selected.contains($0.id) }) else {
            return
        }

        // Uma imagem pertence a no máximo um grupo. Reagrupar dissolve a
        // participação anterior sem perder as legendas das imagens.
        for index in next.rowGroups.indices {
            next.rowGroups[index].itemIDs.removeAll { selected.contains($0) }
        }
        next.rowGroups.removeAll { $0.itemIDs.count < 2 }

        let groupedItems = next.items.filter { selected.contains($0.id) }
        next.items.removeAll { selected.contains($0.id) }
        next.items.insert(contentsOf: groupedItems, at: min(insertionIndex, next.items.count))
        next.rowGroups.append(CompositionRowGroup(itemIDs: orderedIDs))
        next.rowBreaks.subtract(selected)
        next.normalizeOrder()
        commit(next)
        selectedItemID = orderedIDs.first
        selectedItemIDs = Set(orderedIDs)
        showToast("Imagens agrupadas como linha")
    }

    func ungroupSelected() {
        guard let group = selectedGroup else { return }
        var next = state
        next.rowGroups.removeAll { $0.id == group.id }
        next.normalizeOrder()
        commit(next)
        showToast("Linha desagrupada")
    }

    func updateSelectedGroupCaption(_ caption: String) {
        guard let group = selectedGroup,
              let index = state.rowGroups.firstIndex(where: { $0.id == group.id })
        else {
            return
        }
        var next = state
        next.rowGroups[index].caption = caption
        commit(next)
    }

    func setSelectedRowBreak(_ enabled: Bool) {
        guard let id = selectedItemID,
              let item = state.items.first(where: { $0.id == id }),
              item.order > 0,
              selectedGroup == nil
        else {
            return
        }
        var next = state
        if enabled {
            next.rowBreaks.insert(id)
        } else {
            next.rowBreaks.remove(id)
        }
        commit(next)
    }

    func setLayout(_ mode: LayoutMode) {
        var next = state
        next.layoutMode = mode
        commit(next)
    }

    func setAutomaticCropMode(_ mode: AutomaticCropMode) {
        var next = state
        next.automaticCropMode = mode
        commit(next)
    }

    func setOutputWidth(_ width: Int) {
        var next = state
        next.outputProfile.preferredWidth = max(320, min(next.outputProfile.maximumWidth, width))
        commit(next)
    }

    func setSpacing(margin: Int? = nil, horizontal: Int? = nil, vertical: Int? = nil) {
        var next = state
        if let margin { next.outputProfile.outerMargin = max(0, min(200, margin)) }
        if let horizontal { next.outputProfile.horizontalSpacing = max(0, min(100, horizontal)) }
        if let vertical { next.outputProfile.verticalSpacing = max(0, min(100, vertical)) }
        commit(next)
    }

    func applyProfile(_ profile: OutputProfile) {
        var next = state
        next.outputProfile = profile
        commit(next)
    }

    func updateSelected(
        caption: String? = nil,
        crop: NormalizedCrop? = nil,
        primary: Bool? = nil
    ) {
        guard let id = selectedItemID,
              let index = state.items.firstIndex(where: { $0.id == id })
        else { return }
        var next = state
        if let caption { next.items[index].caption = caption }
        if let crop, crop.isValid { next.items[index].crop = crop }
        if let primary {
            for itemIndex in next.items.indices {
                next.items[itemIndex].isPrimary = primary && itemIndex == index
            }
        }
        commit(next)
    }

    func resetSelectedCrop() {
        updateSelected(crop: .zero)
    }

    func newComposition() {
        commit(CompositionState())
        selectedItemID = nil
        selectedItemIDs.removeAll()
    }

    func undo() {
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(state)
        state = previous
        normalizeSelection()
        persistAndRefresh()
    }

    func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(state)
        state = next
        normalizeSelection()
        persistAndRefresh()
    }

    func chooseMonitoringFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Selecione a pasta em que as capturas são gravadas."
        if panel.runModal() == .OK, let url = panel.url {
            startMonitoring(url)
        }
    }

    func toggleMonitoring() {
        if monitor.isRunning {
            stopMonitoring()
        } else {
            let path = UserDefaults.standard.string(forKey: "pastaMonitorada")
                ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].path
            startMonitoring(URL(fileURLWithPath: path))
        }
    }

    func startMonitoring(_ directory: URL) {
        monitor.start(directory: directory) { [weak self] url in
            self?.importFiles([url])
            self?.showToast("Nova captura adicionada")
        }
        UserDefaults.standard.set(true, forKey: "monitoramentoAtivo")
        UserDefaults.standard.set(directory.path, forKey: "pastaMonitorada")
    }

    func stopMonitoring() {
        monitor.stop()
        UserDefaults.standard.set(false, forKey: "monitoramentoAtivo")
    }

    func suspendForVideoRecording() {
        guard !isSuspendedForRecording else { return }
        isSuspendedForRecording = true
        previewTask?.cancel()
        previewTask = nil
        if monitor.isRunning {
            suspendedMonitoringDirectory = monitor.directory
            monitor.stop()
        }
    }

    func resumeAfterVideoRecording() {
        guard isSuspendedForRecording else { return }
        isSuspendedForRecording = false
        if let directory = suspendedMonitoringDirectory,
           UserDefaults.standard.bool(forKey: "monitoramentoAtivo")
        {
            startMonitoring(directory)
        }
        suspendedMonitoringDirectory = nil
        refreshPreview()
    }

    private func commit(_ next: CompositionState) {
        guard next != state else { return }
        undoStates.append(state)
        if undoStates.count > 100 {
            undoStates.removeFirst(undoStates.count - 100)
        }
        redoStates.removeAll()
        state = next
        persistAndRefresh()
    }

    private func importImage(_ image: NSImage) throws {
        var next = state
        let item = try importer.importImage(
            image,
            order: next.items.count,
            automaticCrop: next.automaticCropMode
        )
        next.items.append(item)
        next.normalizeOrder()
        commit(next)
        selectedItemID = item.id
        selectedItemIDs = [item.id]
    }

    private func normalizeSelection() {
        let validIDs = Set(state.items.map(\.id))
        selectedItemIDs.formIntersection(validIDs)
        if let selectedItemID, !validIDs.contains(selectedItemID) {
            self.selectedItemID = selectedItemIDs.first
        }
    }

    private func persistAndRefresh() {
        do {
            try persistence.save(state)
        } catch {
            showError("A sessão não pôde ser salva localmente.")
        }
        refreshPreview()
    }

    private func refreshPreview() {
        previewTask?.cancel()
        let snapshot = state
        previewTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            if snapshot.items.isEmpty {
                self?.previewImage = nil
                self?.previewDimensions = .zero
                self?.approximateFileSize = 0
                return
            }
            do {
                let result = try self?.renderer.render(state: snapshot, width: min(1100, snapshot.outputProfile.preferredWidth))
                guard !Task.isCancelled else { return }
                self?.previewImage = result?.image
                if let result {
                    let ratio = CGFloat(snapshot.outputProfile.preferredWidth) / result.size.width
                    self?.previewDimensions = CGSize(
                        width: CGFloat(snapshot.outputProfile.preferredWidth),
                        height: round(result.size.height * ratio)
                    )
                    self?.approximateFileSize = Int(Double(result.pngData.count) * Double(ratio * ratio))
                } else {
                    self?.previewDimensions = .zero
                    self?.approximateFileSize = 0
                }
            } catch {
                self?.previewImage = nil
                self?.approximateFileSize = 0
            }
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    private func showError(_ message: String) {
        lastErrorMessage = message
    }
}
