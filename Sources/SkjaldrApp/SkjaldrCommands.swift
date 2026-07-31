import AppKit
import SwiftUI

struct SkjaldrCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var workspace: CompositionWorkspace
    @ObservedObject var videoStore: VideoRecorderStore

    private var store: ProjectStore? {
        workspace.activeStore
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nova composição") {
                openCompositionTab()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Nova aba de composição") {
                openCompositionTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Importar imagens…") {
                store?.openImporter()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(store == nil)

            Button("Salvar composição…") {
                store?.saveComposition()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(store?.state.items.isEmpty != false)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Desfazer") {
                store?.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(store?.canUndo != true)

            Button("Refazer") {
                store?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(store?.canRedo != true)

            Divider()

            Button("Recortar") {
                _ = TextEditingSupport.performIfEditing(.cut)
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(store == nil)

            Button("Copiar composição") {
                if !TextEditingSupport.performIfEditing(.copy),
                   store?.state.items.isEmpty == false
                {
                    store?.copyComposition()
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(store == nil)

            Button("Adicionar imagem da área de transferência") {
                if !TextEditingSupport.performIfEditing(.paste) {
                    store?.pasteFromClipboard()
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(store == nil)

            Button("Selecionar tudo") {
                _ = TextEditingSupport.performIfEditing(.selectAll)
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(store == nil)
        }

        CommandMenu("Composição") {
            Button("Layout automático") {
                store?.setLayout(.automatic)
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(store == nil)

            Button("Comparação") {
                store?.setLayout(.comparison)
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(store == nil)

            Button("Grade") {
                store?.setLayout(.grid)
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(store == nil)

            Divider()

            Button("Reorganizar") {
                if let store {
                    store.setLayout(store.state.layoutMode)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(store == nil)

            Button("Duplicar imagem selecionada") {
                store?.duplicateSelected()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(store?.selectedItemID == nil)

            Button("Agrupar seleção como linha") {
                store?.createRowGroup()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(store?.canCreateRowGroup != true)

            Button("Desagrupar linha") {
                store?.ungroupSelected()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(store?.selectedGroup == nil)

            Button("Remover imagem selecionada") {
                store?.removeSelected()
            }
            .disabled(
                store?.selectedItemID == nil &&
                (store?.selectedItemIDs.isEmpty ?? true)
            )

            Divider()

            Button(
                store?.monitor.isRunning == true
                    ? "Parar monitoramento"
                    : "Iniciar monitoramento"
            ) {
                store?.toggleMonitoring()
            }
            .disabled(store == nil)
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

    private var recordingCommandTitle: String {
        switch videoStore.phase {
        case .idle: "Iniciar gravação"
        case .selecting: "Cancelar seleção"
        case .recording: "Parar gravação"
        case .preparing: "Preparando gravação"
        case .finishing: "Finalizando gravação"
        }
    }

    private func openCompositionTab() {
        openWindow(id: "composer")
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            workspace.addTabToActiveWindow()
        }
    }
}
