import SwiftUI

@main
struct SkjaldrApp: App {
    @NSApplicationDelegateAdaptor(SkjaldrApplicationDelegate.self)
    private var appDelegate
    @StateObject private var workspace: CompositionWorkspace
    @StateObject private var videoStore: VideoRecorderStore
    @StateObject private var uploadStore: VideoUploadStore
    private let completionNotificationController:
        VideoCompletionNotificationController
    private let completionBannerController:
        VideoCompletionBannerController

    init() {
        let videoStore = VideoRecorderStore()
        let uploadStore = VideoUploadStore()
        let workspace = CompositionWorkspace(videoStore: videoStore)
        let completionBannerController =
            VideoCompletionBannerController()
        let completionNotificationController =
            VideoCompletionNotificationController {
                [weak completionBannerController] url in
                completionBannerController?.present(url: url)
            }
        uploadStore.onUploadCompleted = {
            [weak completionNotificationController] url in
            completionNotificationController?
                .present(url: url)
        }
        videoStore.onRecordingSaved = { [weak uploadStore] url in
            uploadStore?.enqueue(url)
        }
        uploadStore.onLocalFileDeleted = { [weak videoStore] url in
            videoStore?.forgetLastRecording(ifMatching: url)
        }
        videoStore.onCaptureActivityChanged = {
            [weak workspace, weak uploadStore] active in
            if active {
                workspace?.suspendForVideoRecording()
                uploadStore?.suspendForVideoRecording()
            } else {
                workspace?.resumeAfterVideoRecording()
                uploadStore?.resumeAfterVideoRecording()
            }
        }
        _workspace = StateObject(wrappedValue: workspace)
        _videoStore = StateObject(wrappedValue: videoStore)
        _uploadStore = StateObject(wrappedValue: uploadStore)
        self.completionNotificationController =
            completionNotificationController
        self.completionBannerController = completionBannerController
        appDelegate.videoStore = videoStore
        appDelegate.workspace = workspace
        Task { @MainActor in
            videoStore.startHotKeyMonitoring()
            workspace.startGlobalHotKeyMonitoring()
        }
    }

    var body: some Scene {
        WindowGroup(
            "Skjaldr",
            id: "composer",
            for: CompositionSceneRequest.self
        ) { $request in
            CompositionWindowRoot(
                request: request,
                workspace: workspace,
                videoStore: videoStore,
                uploadStore: uploadStore
            )
        } defaultValue: {
            CompositionSceneRequest.primary
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1240, height: 780)
        .commands {
            SkjaldrCommands(
                workspace: workspace,
                videoStore: videoStore
            )
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(workspace)
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
                .environmentObject(workspace)
                .environmentObject(videoStore)
                .environmentObject(uploadStore)
        }
    }
}

@MainActor
private final class SkjaldrApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var videoStore: VideoRecorderStore?
    weak var workspace: CompositionWorkspace?

    func applicationDidFinishLaunching(_ notification: Notification) {
        videoStore?.startHotKeyMonitoring()
        workspace?.startGlobalHotKeyMonitoring()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            workspace?.showExistingTabOrRequestNew()
        }
        return false
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
    @EnvironmentObject private var workspace: CompositionWorkspace
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
                if let store = workspace.activeStore {
                    Toggle(
                        "Monitorar pasta ao abrir",
                        isOn: Binding(
                            get: { store.monitor.isRunning },
                            set: { _ in store.toggleMonitoring() }
                        )
                    )
                    Button(
                        "Escolher pasta…",
                        action: store.chooseMonitoringFolder
                    )
                } else {
                    Text("Abra uma aba de composição para configurar capturas.")
                        .foregroundStyle(.secondary)
                }
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
        .frame(width: 480, height: 520)
    }
}
