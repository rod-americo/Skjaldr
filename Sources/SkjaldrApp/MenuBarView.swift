import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var workspace: CompositionWorkspace
    @EnvironmentObject private var videoStore: VideoRecorderStore
    @EnvironmentObject private var uploadStore: VideoUploadStore

    var body: some View {
        Group {
            recordingControls

            Divider()

            Picker("Formato", selection: $videoStore.preset) {
                ForEach(PhoneVideoPreset.allCases) { preset in
                    Text(preset.title)
                        .tag(preset)
                }
            }
            .disabled(videoStore.phase != .idle)

            Picker("Áudio", selection: $videoStore.audioMode) {
                ForEach(RecordingAudioMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .disabled(videoStore.phase != .idle)

            if let lastRecordingURL = videoStore.lastRecordingURL {
                Divider()
                Button("Mostrar último vídeo no Finder") {
                    videoStore.revealLastRecording()
                }
                Button("Enviar último vídeo") {
                    uploadStore.enqueue(lastRecordingURL)
                }
            }

            uploadControls

            Divider()

            Button("Mostrar composição") {
                showComposition(addTab: false)
            }

            Button("Nova composição em aba") {
                showComposition(addTab: true)
            }

            SettingsLink {
                Text("Ajustes…")
            }

            Divider()

            Button("Encerrar Skjaldr") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .onAppear {
            videoStore.startHotKeyMonitoring()
        }
    }

    @ViewBuilder
    private var recordingControls: some View {
        switch videoStore.phase {
        case .idle:
            Button("Selecionar região e gravar") {
                videoStore.beginCapture()
            }
        case .selecting:
            Button("Cancelar seleção") {
                videoStore.cancelCurrentOperation()
            }
        case .preparing:
            Label("Preparando gravação…", systemImage: "hourglass")
        case .recording:
            Label(
                "Gravando \(videoStore.elapsedTimeLabel)",
                systemImage: "record.circle.fill"
            )
            Button("Parar e salvar") {
                videoStore.stopRecording()
            }
            Button("Cancelar sem salvar") {
                videoStore.cancelRecording()
            }
        case .finishing:
            Label("Finalizando gravação…", systemImage: "hourglass")
        }
    }

    @ViewBuilder
    private var uploadControls: some View {
        switch uploadStore.phase {
        case .idle:
            EmptyView()
        case .preparing, .uploading, .confirming:
            Divider()
            Label(uploadStore.phase.title, systemImage: "icloud.and.arrow.up")
            if uploadStore.phase == .uploading {
                ProgressView(value: uploadStore.progress)
            }
        case .completed:
            Divider()
            Label("Link criado", systemImage: "checkmark.circle.fill")
            Button("Copiar link") {
                _ = uploadStore.copyLink()
            }
            Button("Abrir link", action: uploadStore.openLink)
        case .failed:
            Divider()
            Label("Upload não concluído", systemImage: "exclamationmark.triangle")
            Button("Tentar novamente", action: uploadStore.retry)
        }
    }

    private func showComposition(addTab: Bool) {
        openWindow(id: "composer")
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard addTab else { return }
        DispatchQueue.main.async {
            workspace.addTabToActiveWindow()
        }
    }
}
