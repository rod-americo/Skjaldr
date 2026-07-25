import SwiftUI

@main
struct SkjaldrApp: App {
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
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
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(store.selectedItemID == nil)
                Divider()
                Button(store.monitor.isRunning ? "Parar monitoramento" : "Iniciar monitoramento") {
                    store.toggleMonitoring()
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: ProjectStore

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
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 270)
    }
}
