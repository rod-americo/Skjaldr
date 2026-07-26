import SwiftUI

@main
struct SkjaldrApp: App {
    @NSApplicationDelegateAdaptor(SkjaldrApplicationDelegate.self)
    private var appDelegate
    @StateObject private var store: ProjectStore
    @StateObject private var videoStore: VideoRecorderStore
    @StateObject private var uploadStore: VideoUploadStore
    private let completionNotificationController:
        VideoCompletionNotificationController

    init() {
        let store = ProjectStore()
        let videoStore = VideoRecorderStore()
        let uploadStore = VideoUploadStore()
        let completionNotificationController =
            VideoCompletionNotificationController()
        uploadStore.onUploadCompleted = {
            [weak completionNotificationController] url in
            completionNotificationController?
                .presentIfApplicationIsInBackground(
                url: url
            )
        }
        videoStore.onRecordingSaved = { [weak uploadStore] url in
            uploadStore?.enqueue(url)
        }
        videoStore.onCaptureActivityChanged = {
            [weak store, weak uploadStore] active in
            if active {
                store?.suspendForVideoRecording()
                uploadStore?.suspendForVideoRecording()
            } else {
                store?.resumeAfterVideoRecording()
                uploadStore?.resumeAfterVideoRecording()
            }
        }
        _store = StateObject(wrappedValue: store)
        _videoStore = StateObject(wrappedValue: videoStore)
        _uploadStore = StateObject(wrappedValue: uploadStore)
        self.completionNotificationController =
            completionNotificationController
        appDelegate.videoStore = videoStore
        Task { @MainActor in
            videoStore.startHotKeyMonitoring()
        }
    }

    var body: some Scene {
        WindowGroup("Skjaldr", id: "composer") {
            ContentView()
                .environmentObject(store)
                .environmentObject(videoStore)
                .environmentObject(uploadStore)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nova composição") {
                    store.newComposition()
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Importar imagens…") {
                    store.openImporter()
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("Salvar composição…") {
                    store.saveComposition()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(store.state.items.isEmpty)
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Desfazer") { store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
                Button("Refazer") { store.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!store.canRedo)
                Divider()
                Button("Copiar composição") { store.copyComposition() }
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(store.state.items.isEmpty)
                Button("Adicionar imagem da área de transferência") { store.pasteFromClipboard() }
                    .keyboardShortcut("v", modifiers: .command)
            }

            CommandMenu("Composição") {
                Button("Layout automático") { store.setLayout(.automatic) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Comparação") { store.setLayout(.comparison) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Grade") { store.setLayout(.grid) }
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("Reorganizar") { store.setLayout(store.state.layoutMode) }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Duplicar imagem selecionada") { store.duplicateSelected() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(store.selectedItemID == nil)
                Button("Agrupar seleção como linha") { store.createRowGroup() }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(!store.canCreateRowGroup)
                Button("Desagrupar linha") { store.ungroupSelected() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(store.selectedGroup == nil)
                Button("Remover imagem selecionada") { store.removeSelected() }
                    .disabled(store.selectedItemID == nil && store.selectedItemIDs.isEmpty)
                Divider()
                Button(store.monitor.isRunning ? "Parar monitoramento" : "Iniciar monitoramento") {
                    store.toggleMonitoring()
                }
            }

            CommandMenu("Captura") {
                Button("Configurar gravação…") {
                    videoStore.showConfiguration()
                }
                .disabled(videoStore.phase != .idle)

                Divider()

                Button(recordingCommandTitle) {
                    videoStore.handleRecordingShortcut()
                }
                .keyboardShortcut("9", modifiers: [.command, .shift])
                .disabled(
                    videoStore.phase == .preparing ||
                    videoStore.phase == .finishing
                )

                Button("Cancelar gravação sem salvar") {
                    videoStore.cancelRecording()
                }
                .keyboardShortcut(
                    "9",
                    modifiers: [.command, .shift, .option]
                )
                .disabled(videoStore.phase != .recording)

                if videoStore.lastRecordingURL != nil {
                    Divider()
                    Button("Mostrar último vídeo no Finder") {
                        videoStore.revealLastRecording()
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(videoStore)
                .environmentObject(uploadStore)
        } label: {
            Group {
                if videoStore.phase == .recording {
                    Image(systemName: "record.circle.fill")
                } else if videoStore.phase == .finishing {
                    Image(systemName: "hourglass.circle")
                } else {
                    Image("MenuBarIcon")
                }
            }
            .accessibilityLabel("Skjaldr")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(videoStore)
                .environmentObject(uploadStore)
        }
    }

    private var recordingCommandTitle: String {
        switch videoStore.phase {
        case .idle: "Iniciar gravação"
        case .selecting: "Cancelar seleção"
        case .recording: "Parar gravação"
        case .preparing: "Preparando gravação"
        case .finishing: "Finalizando gravação"
        }
    }
}

@MainActor
private final class SkjaldrApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var videoStore: VideoRecorderStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        videoStore?.startHotKeyMonitoring()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let videoStore, videoStore.phase != .idle else {
            return .terminateNow
        }
        videoStore.prepareForApplicationTermination {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var videoStore: VideoRecorderStore
    @EnvironmentObject private var uploadStore: VideoUploadStore

    var body: some View {
        Form {
            Section("Privacidade") {
                Label("Composição de imagens local", systemImage: "lock.shield")
                Text(
                    """
                    Imagens permanecem no Mac. Vídeos são mantidos localmente \
                    e enviados somente pelo fluxo configurado do Skjaldr.
                    """
                )
                    .foregroundStyle(.secondary)
            }
            Section("Capturas") {
                Toggle(
                    "Monitorar pasta ao abrir",
                    isOn: Binding(
                        get: { store.monitor.isRunning },
                        set: { _ in store.toggleMonitoring() }
                    )
                )
                Button("Escolher pasta…", action: store.chooseMonitoringFolder)
            }
            Section("Vídeo") {
                LabeledContent("Pasta de saída") {
                    Text(videoStore.outputDirectory.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button("Escolher pasta de vídeos…", action: videoStore.chooseOutputDirectory)
                Toggle(
                    "Remover arquivo local após upload confirmado",
                    isOn: $uploadStore.deleteLocalAfterUpload
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 360)
    }
}
