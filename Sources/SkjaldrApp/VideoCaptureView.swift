import SwiftUI

struct VideoCaptureView: View {
    @EnvironmentObject private var videoStore: VideoRecorderStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Captura de vídeo")
                        .font(.title2.weight(.semibold))
                    Text("Escolha o formato e arraste a região que será gravada.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "record.circle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.red)
            }
            .padding(24)

            Divider()

            Form {
                Section("Formato") {
                    Picker("Orientação", selection: $videoStore.preset) {
                        ForEach(PhoneVideoPreset.allCases) { preset in
                            Label(preset.title, systemImage: preset.systemImage)
                                .tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Saída") {
                        Text(outputDescription)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Section("Áudio") {
                    Picker("Fonte", selection: $videoStore.audioMode) {
                        ForEach(RecordingAudioMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if videoStore.audioMode.capturesMicrophone {
                        if videoStore.microphones.isEmpty {
                            Label(
                                "Nenhum microfone disponível",
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(.orange)
                        } else {
                            Picker(
                                "Microfone",
                                selection: Binding(
                                    get: {
                                        videoStore.selectedMicrophoneID
                                            ?? videoStore.microphones.first?.id
                                            ?? ""
                                    },
                                    set: { videoStore.selectedMicrophoneID = $0 }
                                )
                            ) {
                                ForEach(videoStore.microphones) { microphone in
                                    Text(microphone.name).tag(microphone.id)
                                }
                            }
                        }
                    }
                }

                Section("Destino") {
                    LabeledContent("Pasta") {
                        Text(videoStore.outputDirectory.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button(
                        "Escolher pasta…",
                        action: videoStore.chooseOutputDirectory
                    )
                }

                Section {
                    Label(
                        "MP4 • H.264 • 30 fps"
                            + (videoStore.audioMode == .none ? "" : " • AAC"),
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text("⌘⇧9 inicia ou para usando estas escolhas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar") {
                    videoStore.isConfigurationPresented = false
                }
                Button("Selecionar região") {
                    videoStore.beginCapture()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    videoStore.audioMode.capturesMicrophone &&
                    videoStore.microphones.isEmpty
                )
            }
            .padding(18)
        }
        .frame(width: 520, height: 520)
        .onAppear {
            videoStore.refreshMicrophones()
        }
    }

    private var outputDescription: String {
        let size = videoStore.preset.outputSize
        return "\(Int(size.width)) × \(Int(size.height))"
    }
}
