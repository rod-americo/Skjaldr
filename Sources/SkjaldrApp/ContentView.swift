import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ImageDeletionShortcut {
    static func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let isDeleteKey = keyCode == 51 || keyCode == 117
        let conflictingModifiers = modifiers.intersection([.command, .control, .option])
        return isDeleteKey && conflictingModifiers.isEmpty
    }

    static func matches(_ event: NSEvent) -> Bool {
        matches(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
    }
}

enum CompositionTabCloseShortcut {
    static func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let normalized = modifiers.intersection(.deviceIndependentFlagsMask)
        let conflicting = normalized.intersection([.control, .option, .shift])
        return keyCode == 13 &&
            normalized.contains(.command) &&
            conflicting.isEmpty
    }

    static func matches(_ event: NSEvent) -> Bool {
        matches(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var windowController:
        CompositionWindowController
    @EnvironmentObject private var videoStore: VideoRecorderStore
    @EnvironmentObject private var uploadStore: VideoUploadStore
    @State private var isDropTarget = false
    @State private var previewScale: CGFloat = 0.82
    @State private var deleteKeyMonitor: Any?
    let windowID: UUID

    var body: some View {
        HSplitView {
            thumbnailPanel
                .frame(minWidth: 190, idealWidth: 220, maxWidth: 280)

            compositionPanel
                .frame(minWidth: 480)

            inspectorPanel
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 330)
        }
        .frame(minWidth: 980, minHeight: 620)
        .toolbar { toolbar }
        .overlay(alignment: .top) {
            if let message = videoStore.toastMessage ?? store.toastMessage {
                Text(message)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if videoStore.phase == .recording || videoStore.phase == .finishing {
                recordingIndicator
                    .padding(.top, 11)
                    .padding(.trailing, 14)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if uploadStore.phase != .idle &&
                (
                    uploadStore.phase != .completed ||
                    uploadStore.isCompletionIndicatorVisible
                )
            {
                uploadIndicator
                    .padding(.bottom, 14)
                    .padding(.trailing, 14)
            }
        }
        .alert(
            "Não foi possível concluir",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.lastErrorMessage = nil } }
            ),
            actions: { Button("OK") { store.lastErrorMessage = nil } },
            message: { Text(store.lastErrorMessage ?? "") }
        )
        .alert(
            "Não foi possível gravar",
            isPresented: Binding(
                get: { videoStore.lastErrorMessage != nil },
                set: { if !$0 { videoStore.clearError() } }
            ),
            actions: {
                if let target = videoStore.privacySettingsTarget {
                    Button(target.buttonTitle) {
                        videoStore.openRelevantPrivacySettings()
                    }
                }
                Button("OK") {
                    videoStore.clearError()
                }
            },
            message: { Text(videoStore.lastErrorMessage ?? "") }
        )
        .sheet(isPresented: $videoStore.isConfigurationPresented) {
            VideoCaptureView()
                .environmentObject(videoStore)
        }
        .onAppear {
            videoStore.startHotKeyMonitoring()
            startDeleteKeyMonitoring()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSControl.textDidBeginEditingNotification
            )
        ) { notification in
            TextEditingSupport.enableSystemSpelling(
                from: notification,
                in: NSApp.keyWindow
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSControl.textDidEndEditingNotification
            )
        ) { notification in
            TextEditingSupport.finishEditing(from: notification)
        }
        .onDisappear {
            stopDeleteKeyMonitoring()
        }
        .onDeleteCommand {
            guard store.selectedItemID != nil || !store.selectedItemIDs.isEmpty else {
                return
            }
            store.removeSelected()
        }
        .animation(.easeOut(duration: 0.18), value: store.toastMessage)
    }

    private func startDeleteKeyMonitoring() {
        guard deleteKeyMonitor == nil else { return }
        deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let keyWindow = NSApp.keyWindow,
                  keyWindow.identifier?.rawValue ==
                    "io.skjaldr.composer.\(windowID.uuidString)"
            else {
                return event
            }

            if let action = TextEditingShortcut.action(for: event),
               TextEditingSupport.performIfEditing(action)
            {
                return nil
            }

            if CompositionTabCloseShortcut.matches(event) {
                DispatchQueue.main.async {
                    windowController.closeActiveTab()
                }
                return nil
            }

            guard ImageDeletionShortcut.matches(event),
                  !(keyWindow.firstResponder is NSTextView),
                  store.selectedItemID != nil || !store.selectedItemIDs.isEmpty
            else {
                return event
            }
            store.removeSelected()
            return nil
        }
    }

    private func stopDeleteKeyMonitoring() {
        guard let deleteKeyMonitor else { return }
        NSEvent.removeMonitor(deleteKeyMonitor)
        self.deleteKeyMonitor = nil
    }

    private var recordingIndicator: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(.red)
                .frame(width: 9, height: 9)
            Text(videoStore.phase == .finishing ? "Finalizando" : "REC")
                .font(.caption.weight(.bold))
            if videoStore.phase == .recording {
                Text(videoStore.elapsedTimeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Parar", action: videoStore.stopRecording)
                    .controlSize(.small)
                Button("Cancelar", action: videoStore.cancelRecording)
                    .controlSize(.small)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 8, y: 3)
    }

    private var uploadIndicator: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(
                    systemName: uploadStore.phase == .completed
                        ? "checkmark.circle.fill"
                        : uploadStore.phase == .failed
                            ? "exclamationmark.triangle.fill"
                            : "icloud.and.arrow.up"
                )
                .foregroundStyle(
                    uploadStore.phase == .completed
                        ? .green
                        : uploadStore.phase == .failed ? .orange : .blue
                )
                Text(uploadStore.phase.title)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 12)
                if uploadStore.phase == .completed {
                    Button(
                        action: uploadStore.dismissCompletionIndicator
                    ) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Fechar")
                    .accessibilityLabel("Fechar aviso de upload")
                }
            }

            if uploadStore.phase == .uploading {
                ProgressView(value: uploadStore.progress)
                    .frame(width: 260)
                Text(
                    "\(ByteCountFormatter.string(fromByteCount: uploadStore.sentBytes, countStyle: .file)) de "
                        + ByteCountFormatter.string(
                            fromByteCount: uploadStore.totalBytes,
                            countStyle: .file
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let url = uploadStore.publicURL {
                Text(url.absoluteString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                HStack {
                    Button("Copiar link") {
                        _ = uploadStore.copyLink()
                    }
                    Button("Abrir", action: uploadStore.openLink)
                }
                .controlSize(.small)
            }

            if let error = uploadStore.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 280, alignment: .leading)
                Button("Tentar novamente", action: uploadStore.retry)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 8, y: 3)
    }

    private var thumbnailPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Imagens")
                    .font(.headline)
                Spacer()
                Text("\(store.state.items.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding()

            Divider()

            if store.state.items.isEmpty {
                ContentUnavailableView(
                    "Nenhuma imagem",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Cole com ⌘V ou arraste capturas para esta janela.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.state.items.sorted(by: { $0.order < $1.order })) { item in
                            let isGrouped = store.state.rowGroups.contains {
                                $0.itemIDs.contains(item.id)
                            }
                            let startsNewRow = store.state.rowBreaks.contains(item.id)
                            ThumbnailRow(
                                item: item,
                                isSelected: store.selectedItemIDs.contains(item.id),
                                isGrouped: isGrouped,
                                startsNewRow: startsNewRow
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                                let modifiers = NSEvent.modifierFlags
                                store.selectItem(
                                    item.id,
                                    extending: modifiers.contains(.command) || modifiers.contains(.shift)
                                )
                            }
                            .onDrag {
                                NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: ThumbnailReorderDelegate(targetID: item.id, store: store)
                            )
                            .contextMenu {
                                Button(item.isPrimary ? "Remover destaque" : "Definir como principal") {
                                    store.selectItem(item.id, extending: false)
                                    store.updateSelected(primary: !item.isPrimary)
                                }
                                Button("Duplicar") {
                                    store.selectItem(item.id, extending: false)
                                    store.duplicateSelected()
                                }
                                if item.order > 0, !isGrouped {
                                    Button(
                                        startsNewRow
                                            ? "Remover quebra de linha"
                                            : "Iniciar nova linha aqui"
                                    ) {
                                        store.selectItem(item.id, extending: false)
                                        store.setSelectedRowBreak(!startsNewRow)
                                    }
                                }
                                if isGrouped {
                                    Button("Desagrupar linha") {
                                        store.selectItem(item.id, extending: false)
                                        store.ungroupSelected()
                                    }
                                }
                                Divider()
                                Button("Remover", role: .destructive) {
                                    store.selectItem(item.id, extending: false)
                                    store.removeSelected()
                                }
                            }
                        }
                    }
                    .padding(10)
                }
            }

            Divider()
            HStack {
                Button(action: store.openImporter) {
                    Label("Adicionar", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button(action: store.removeSelected) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(store.selectedItemIDs.isEmpty)
                .help("Remover imagem selecionada")
            }
            .padding(12)

            if store.selectedItemIDs.count > 1 {
                Divider()
                HStack {
                    Text("\(store.selectedItemIDs.count) imagens selecionadas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Agrupar como linha", action: store.createRowGroup)
                        .controlSize(.small)
                        .disabled(!store.canCreateRowGroup)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
        }
        .background(.background)
    }

    private var compositionPanel: some View {
        ZStack {
            Color(nsColor: NSColor.windowBackgroundColor.blended(
                withFraction: 0.20,
                of: .black
            ) ?? .windowBackgroundColor)

            if let preview = store.previewImage {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 12) {
                        Image(nsImage: preview)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: max(240, preview.size.width * previewScale),
                                height: max(160, preview.size.height * previewScale)
                            )
                            .background(Color.white)
                            .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
                            .onDrag { store.dragProvider() }

                        Label("Arraste como PNG", systemImage: "arrow.up.doc")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .onDrag { store.dragProvider() }
                    }
                    .padding(40)
                    .help("Arraste a composição como arquivo PNG para outro aplicativo")
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 52, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                    Text("Cole, selecione ou arraste imagens")
                        .font(.title3)
                    Text("A composição será reorganizada automaticamente.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Colar imagem", action: store.pasteFromClipboard)
                            .keyboardShortcut("v", modifiers: .command)
                        Button("Selecionar arquivos…", action: store.openImporter)
                    }
                }
            }

            if isDropTarget {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 4, dash: [10]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    .padding(18)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier], isTargeted: $isDropTarget) {
            handleDrop($0)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 14) {
                if store.previewDimensions != .zero {
                    Text(
                        "\(Int(store.previewDimensions.width)) × \(Int(store.previewDimensions.height)) px"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(store.approximateFileSize),
                        countStyle: .file
                    ) + " aprox.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.secondary)
                Slider(value: $previewScale, in: 0.25...1.25)
                    .frame(width: 130)
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.bar)
        }
    }

    private var inspectorPanel: some View {
        Form {
            Section("Composição") {
                Picker(
                    "Layout",
                    selection: Binding(
                        get: { store.state.layoutMode },
                        set: store.setLayout
                    )
                ) {
                    ForEach(LayoutMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker(
                    "Perfil",
                    selection: Binding(
                        get: { store.state.outputProfile.name },
                        set: { name in
                            let profile: OutputProfile = switch name {
                            case OutputProfile.highResolution.name: .highResolution
                            case OutputProfile.compact.name: .compact
                            default: .report
                            }
                            store.applyProfile(profile)
                        }
                    )
                ) {
                    Text(OutputProfile.report.name).tag(OutputProfile.report.name)
                    Text(OutputProfile.highResolution.name).tag(OutputProfile.highResolution.name)
                    Text(OutputProfile.compact.name).tag(OutputProfile.compact.name)
                }

                Stepper(
                    "Largura: \(store.state.outputProfile.preferredWidth) px",
                    value: Binding(
                        get: { store.state.outputProfile.preferredWidth },
                        set: store.setOutputWidth
                    ),
                    in: 320...store.state.outputProfile.maximumWidth,
                    step: 50
                )

                Stepper(
                    "Margem: \(store.state.outputProfile.outerMargin) px",
                    value: Binding(
                        get: { store.state.outputProfile.outerMargin },
                        set: { store.setSpacing(margin: $0) }
                    ),
                    in: 0...200
                )
                Stepper(
                    "Espaçamento: \(store.state.outputProfile.horizontalSpacing) px",
                    value: Binding(
                        get: { store.state.outputProfile.horizontalSpacing },
                        set: { store.setSpacing(horizontal: $0, vertical: $0) }
                    ),
                    in: 0...100
                )
            }

            Section("Capturas") {
                Toggle(
                    "Monitorar pasta",
                    isOn: Binding(
                        get: { store.monitor.isRunning },
                        set: { _ in store.toggleMonitoring() }
                    )
                )
                if let directory = store.monitor.directory {
                    Text(directory.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Escolher pasta…", action: store.chooseMonitoringFolder)
                }
                Picker(
                    "Recorte ao importar",
                    selection: Binding(
                        get: { store.state.automaticCropMode },
                        set: store.setAutomaticCropMode
                    )
                ) {
                    ForEach(AutomaticCropMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }

            if let item = store.selectedItem {
                Section("Imagem selecionada") {
                    Toggle(
                        "Imagem principal",
                        isOn: Binding(
                            get: { item.isPrimary },
                            set: { store.updateSelected(primary: $0) }
                        )
                    )
                    Toggle(
                        "Iniciar nova linha",
                        isOn: Binding(
                            get: { store.state.rowBreaks.contains(item.id) },
                            set: store.setSelectedRowBreak
                        )
                    )
                    .disabled(item.order == 0 || store.selectedGroup != nil)
                    .help("Força uma quebra antes desta imagem em qualquer modo de layout")
                    TextField(
                        "Legenda da imagem",
                        text: Binding(
                            get: { store.selectedItem?.caption ?? "" },
                            set: { store.updateSelected(caption: $0) }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                    CropControls(store: store)
                }
            }

            if let group = store.selectedGroup {
                Section("Linha agrupada") {
                    Text("\(group.itemIDs.count) imagens mantidas na mesma linha")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(
                        "Legenda central da linha",
                        text: Binding(
                            get: { store.selectedGroup?.caption ?? "" },
                            set: store.updateSelectedGroupCaption
                        ),
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                    Button("Desagrupar linha", action: store.ungroupSelected)
                }
            } else if store.selectedItemIDs.count > 1 {
                Section("Legenda da linha") {
                    Text("Agrupe as imagens para mantê-las juntas e adicionar uma legenda comum.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Agrupar como linha", action: store.createRowGroup)
                        .disabled(!store.canCreateRowGroup)
                }
            }

            Section {
                Button(action: store.copyComposition) {
                    Label("Copiar composição", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.state.items.isEmpty)

                HStack {
                    Button("Salvar…", action: store.saveComposition)
                        .disabled(store.state.items.isEmpty)
                    Button("Compartilhar…", action: store.shareComposition)
                        .disabled(store.state.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.background)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: store.openImporter) {
                Label("Adicionar", systemImage: "photo.badge.plus")
            }
            Button(action: store.pasteFromClipboard) {
                Label("Colar", systemImage: "doc.on.clipboard")
            }
        }
        ToolbarItemGroup {
            Picker(
                "Layout",
                selection: Binding(
                    get: { store.state.layoutMode },
                    set: store.setLayout
                )
            ) {
                ForEach(LayoutMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: icon(for: mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 330)
        }
        ToolbarItemGroup {
            Button(action: videoStore.showConfiguration) {
                Label("Gravar tela", systemImage: "record.circle")
            }
            .disabled(videoStore.phase != .idle)
            Button(action: store.copyComposition) {
                Label("Copiar composição", systemImage: "doc.on.doc")
            }
            .disabled(store.state.items.isEmpty)
            .keyboardShortcut("c", modifiers: .command)
        }
    }

    private func icon(for mode: LayoutMode) -> String {
        switch mode {
        case .automatic: "wand.and.stars"
        case .grid: "square.grid.2x2"
        case .comparison: "rectangle.split.2x1"
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                    let url: URL?
                    if let data = value as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let value = value as? URL {
                        url = value
                    } else {
                        url = nil
                    }
                    if let url {
                        Task { @MainActor in store.importFiles([url]) }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                accepted = true
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    Task { @MainActor in
                        store.importDroppedImage(image)
                    }
                }
            }
        }
        return accepted
    }
}

private struct ThumbnailRow: View {
    let item: CompositionItem
    let isSelected: Bool
    let isGrouped: Bool
    let startsNewRow: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let image = NSImage(contentsOf: item.sourceURL) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 48)
            .clipped()
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("Imagem \(item.order + 1)")
                        .font(.callout.weight(.medium))
                    if item.isPrimary {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    if isGrouped {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if startsNewRow {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Esta imagem inicia uma nova linha")
                    }
                }
                Text("\(item.originalWidth) × \(item.originalHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .background(
            isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
            }
        }
    }
}

private struct CropControls: View {
    @ObservedObject var store: ProjectStore

    var body: some View {
        DisclosureGroup("Recorte manual") {
            cropSlider("Superior", keyPath: \.top)
            cropSlider("Inferior", keyPath: \.bottom)
            cropSlider("Esquerda", keyPath: \.left)
            cropSlider("Direita", keyPath: \.right)
            Button("Restaurar original", action: store.resetSelectedCrop)
                .controlSize(.small)
        }
    }

    private func cropSlider(
        _ label: String,
        keyPath: WritableKeyPath<NormalizedCrop, Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text("\(Int((store.selectedItem?.crop[keyPath: keyPath] ?? 0) * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { store.selectedItem?.crop[keyPath: keyPath] ?? 0 },
                    set: { value in
                        guard var crop = store.selectedItem?.crop else { return }
                        crop[keyPath: keyPath] = value
                        store.updateSelected(crop: crop)
                    }
                ),
                in: 0...0.35
            )
        }
    }
}

private struct ThumbnailReorderDelegate: DropDelegate {
    let targetID: UUID
    let store: ProjectStore

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else { return }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let text = value as? String, let id = UUID(uuidString: text) else { return }
            Task { @MainActor in
                store.moveItem(id: id, before: targetID)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool { true }
}
