import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var videoStore: VideoRecorderStore
    @EnvironmentObject private var uploadStore: VideoUploadStore

    var body: some View {
        Group {
            recordingControls

            Divider()

            Menu("Formato") {
                ForEach(PhoneVideoPreset.allCases) { preset in
                    Button {
                        videoStore.preset = preset
                    } label: {
                        if videoStore.preset == preset {
                            Label(preset.title, systemImage: "checkmark")
                        } else {
                            Text(preset.title)
                        }
                    }
                }
            }
            .disabled(videoStore.phase != .idle)

            Menu("Áudio") {
                ForEach(RecordingAudioMode.allCases) { mode in
                    Button {
                        videoStore.audioMode = mode
                    } label: {
                        if videoStore.audioMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
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

            Button("Nova janela de composição") {
                openWindow(id: "composer", value: CompositionSceneRequest.newWindow())
                NSApp.activate(ignoringOtherApps: true)
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
            Button("Copiar link", action: uploadStore.copyLink)
            Button("Abrir link", action: uploadStore.openLink)
        case .failed:
            Divider()
            Label("Upload não concluído", systemImage: "exclamationmark.triangle")
            Button("Tentar novamente", action: uploadStore.retry)
        }
    }
}
