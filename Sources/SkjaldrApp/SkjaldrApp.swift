import SwiftUI

@main
struct SkjaldrApp: App {
    @NSApplicationDelegateAdaptor(SkjaldrApplicationDelegate.self)
    private var appDelegate
    @StateObject private var store: ProjectStore
    @StateObject private var videoStore: VideoRecorderStore
    @StateObject private var uploadStore: VideoUploadStore

    init() {
        let store = ProjectStore()
        let videoStore = VideoRecorderStore()
        let uploadStore = VideoUploadStore()
        videoStore.onRecordingSaved = { [weak uploadStore] url in
            uploadStore?.enqueue(url)
        }
        _store = StateObject(wrappedValue: store)
        _videoStore = StateObject(wrappedValue: videoStore)
        _uploadStore = StateObject(wrappedValue: uploadStore)
        appDelegate.videoStore = videoStore
    }

    var body: some Scene {
        WindowGroup {
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

                if videoStore.lastRecordingURL != nil {
                    Divider()
                    Button("Mostrar último vídeo no Finder") {
                        videoStore.revealLastRecording()
                    }
                }
            }
        }

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
                Label("Processamento integralmente local", systemImage: "lock.shield")
                Text("O Skjaldr não contém clientes de rede, telemetria ou serviços externos.")
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
