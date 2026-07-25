import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Foundation

@MainActor
final class VideoRecorderStore: ObservableObject {
    @Published var preset: PhoneVideoPreset {
        didSet { preferences.preset = preset }
    }
    @Published var audioMode: RecordingAudioMode {
        didSet { preferences.audioMode = audioMode }
    }
    @Published var selectedMicrophoneID: String? {
        didSet { preferences.microphoneID = selectedMicrophoneID }
    }
    @Published var outputDirectory: URL {
        didSet { preferences.outputDirectory = outputDirectory }
    }
    @Published private(set) var microphones: [MicrophoneSource]
    @Published private(set) var phase: VideoRecordingPhase = .idle
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var lastRecordingURL: URL?
    @Published var isConfigurationPresented = false
    @Published var lastErrorMessage: String?
    @Published var toastMessage: String?

    private let preferences: VideoCapturePreferences
    private let selector = VideoRegionSelectionController()
    private let recorder = ScreenCaptureRecorder()
    private var operationTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var terminationCompletion: (() -> Void)?
    private var isHotKeyRegistered = false
    private lazy var hotKey = GlobalHotKeyController { [weak self] in
        Task { @MainActor in
            self?.handleRecordingShortcut()
        }
    }

    init(preferences: VideoCapturePreferences = VideoCapturePreferences()) {
        self.preferences = preferences
        preset = preferences.preset
        audioMode = preferences.audioMode
        outputDirectory = preferences.outputDirectory
        microphones = MicrophoneSource.available()

        let savedID = preferences.microphoneID
        selectedMicrophoneID = microphones.contains(where: { $0.id == savedID })
            ? savedID
            : microphones.first?.id
        recorder.onUnexpectedFailure = { [weak self] error in
            self?.handleUnexpectedFailure(error)
        }
    }

    var isRecording: Bool { phase == .recording }

    var elapsedTimeLabel: String {
        let totalSeconds = max(0, Int(elapsedTime))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func startHotKeyMonitoring() {
        guard !isHotKeyRegistered else { return }
        isHotKeyRegistered = hotKey.register()
        if !isHotKeyRegistered {
            showToast("⌘⇧9 indisponível; use o botão de gravação")
        }
    }

    func showConfiguration() {
        guard phase == .idle else { return }
        refreshMicrophones()
        isConfigurationPresented = true
    }

    func refreshMicrophones() {
        microphones = MicrophoneSource.available()
        if !microphones.contains(where: { $0.id == selectedMicrophoneID }) {
            selectedMicrophoneID = microphones.first?.id
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Selecione a pasta em que os vídeos serão gravados."
        panel.directoryURL = outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }

    func beginCapture() {
        guard phase == .idle else { return }
        operationTask?.cancel()
        isConfigurationPresented = false
        operationTask = Task { @MainActor [weak self] in
            await self?.selectAndStart()
        }
    }

    func stopRecording() {
        guard phase == .recording else { return }
        operationTask?.cancel()
        operationTask = Task { @MainActor [weak self] in
            await self?.finishRecording()
        }
    }

    func cancelCurrentOperation() {
        switch phase {
        case .idle:
            isConfigurationPresented = false
        case .selecting:
            selector.cancel()
        case .preparing:
            operationTask?.cancel()
            Task { await recorder.cancel() }
            resetToIdle()
        case .recording:
            stopRecording()
        case .finishing:
            break
        }
    }

    func handleRecordingShortcut() {
        switch phase {
        case .idle:
            beginCapture()
        case .selecting:
            selector.cancel()
        case .recording:
            stopRecording()
        case .preparing, .finishing:
            NSSound.beep()
        }
    }

    func revealLastRecording() {
        guard let lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastRecordingURL])
    }

    func openOutputDirectory() {
        NSWorkspace.shared.open(outputDirectory)
    }

    func prepareForApplicationTermination(completion: @escaping () -> Void) {
        isConfigurationPresented = false
        switch phase {
        case .idle:
            completion()
        case .recording:
            terminationCompletion = completion
            stopRecording()
        case .finishing:
            terminationCompletion = completion
        case .selecting, .preparing:
            terminationCompletion = completion
            selector.cancel()
            operationTask?.cancel()
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.recorder.cancel()
                self.resetToIdle()
            }
        }
    }

    private func selectAndStart() async {
        phase = .selecting
        let storedRegion = preferences.storedRegion(for: preset)
        guard let selection = await selector.selectRegion(
            preset: preset,
            restoring: storedRegion
        ) else {
            resetToIdle()
            return
        }
        guard !Task.isCancelled else {
            resetToIdle()
            return
        }

        preferences.setStoredRegion(
            StoredCaptureRegion(selection: selection),
            for: preset
        )
        phase = .preparing

        do {
            try await requestRequiredPermissions()
            try validateAudioSelection()
            try await recorder.start(
                selection: selection,
                preset: preset,
                audioMode: audioMode,
                microphoneID: selectedMicrophoneID,
                outputDirectory: outputDirectory
            )
            guard !Task.isCancelled else {
                await recorder.cancel()
                resetToIdle()
                return
            }
            phase = .recording
            elapsedTime = 0
            startDurationUpdates()
            showToast("Gravação iniciada")
        } catch is CancellationError {
            await recorder.cancel()
            resetToIdle()
        } catch {
            await recorder.cancel()
            resetToIdle()
            showError(error)
        }
    }

    private func finishRecording() async {
        phase = .finishing
        durationTask?.cancel()
        do {
            let url = try await recorder.stop()
            lastRecordingURL = url
            resetToIdle()
            showToast("Vídeo salvo: \(url.lastPathComponent)")
        } catch {
            resetToIdle()
            showError(error)
        }
    }

    private func requestRequiredPermissions() async throws {
        if !CGPreflightScreenCaptureAccess() {
            // No macOS 26, o preflight pode continuar retornando `false` para
            // builds locais ad hoc mesmo quando o app está habilitado em
            // Privacidade. Solicitar o acesso continua correto, mas a decisão
            // final deve vir do ScreenCaptureKit ao abrir o stream.
            _ = CGRequestScreenCaptureAccess()
        }

        guard audioMode.capturesMicrophone else { return }
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            granted = false
        @unknown default:
            granted = false
        }
        guard granted else {
            throw VideoRecordingError.microphonePermissionDenied
        }
    }

    private func validateAudioSelection() throws {
        guard audioMode.capturesMicrophone else { return }
        refreshMicrophones()
        guard let selectedMicrophoneID,
              microphones.contains(where: { $0.id == selectedMicrophoneID })
        else {
            throw VideoRecordingError.noMicrophone
        }
    }

    private func startDurationUpdates() {
        durationTask?.cancel()
        durationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.phase == .recording else { return }
                self.elapsedTime = self.recorder.recordedDuration
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func resetToIdle() {
        durationTask?.cancel()
        durationTask = nil
        elapsedTime = 0
        phase = .idle
        let completion = terminationCompletion
        terminationCompletion = nil
        completion?()
    }

    private func handleUnexpectedFailure(_ error: Error) {
        guard phase == .recording else { return }
        durationTask?.cancel()
        operationTask?.cancel()
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.recorder.cancel()
            self.resetToIdle()
            self.showError(error)
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    private func showError(_ error: Error) {
        lastErrorMessage = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }
}
