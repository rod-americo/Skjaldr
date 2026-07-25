import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

@MainActor
final class ScreenCaptureRecorder: NSObject {
    var onUnexpectedFailure: ((Error) -> Void)?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var temporaryURL: URL?
    private var destinationURL: URL?
    private var didStart = false

    var recordedDuration: TimeInterval {
        guard let recordingOutput else { return 0 }
        let seconds = recordingOutput.recordedDuration.seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }

    var recordedFileSize: Int64 {
        Int64(recordingOutput?.recordedFileSize ?? 0)
    }

    func start(
        selection: CaptureSelection,
        preset: PhoneVideoPreset,
        audioMode: RecordingAudioMode,
        microphoneID: String?,
        outputDirectory: URL
    ) async throws {
        guard stream == nil else { return }
        guard VideoRegionGeometry.isValid(
            selection.region,
            aspectRatio: preset.aspectRatio
        ) else {
            throw VideoRecordingError.invalidRegion
        }

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard FileManager.default.isWritableFile(atPath: outputDirectory.path) else {
            throw VideoRecordingError.outputFolderUnavailable
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let display = content.displays.first(where: {
            $0.displayID == selection.displayID
        }) else {
            throw VideoRecordingError.displayUnavailable
        }

        let ownApplications = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = selection.sourceRect
        configuration.width = Int(preset.outputSize.width)
        configuration.height = Int(preset.outputSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.destinationRect = CGRect(origin: .zero, size: preset.outputSize)
        configuration.showsCursor = true
        configuration.shouldBeOpaque = true
        configuration.captureResolution = .best

        configuration.capturesAudio = audioMode.capturesSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.captureMicrophone = audioMode.capturesMicrophone
        if audioMode.capturesMicrophone {
            configuration.microphoneCaptureDeviceID = microphoneID
        }

        let destination = Self.availableDestination(in: outputDirectory)
        let temporary = outputDirectory.appendingPathComponent(
            ".skjaldr-\(UUID().uuidString).mp4"
        )
        try? FileManager.default.removeItem(at: temporary)

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = temporary
        outputConfiguration.videoCodecType = .h264
        outputConfiguration.outputFileType = .mp4

        let output = SCRecordingOutput(
            configuration: outputConfiguration,
            delegate: self
        )
        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addRecordingOutput(output)

        self.stream = stream
        recordingOutput = output
        temporaryURL = temporary
        destinationURL = destination
        didStart = false

        do {
            try await withCheckedThrowingContinuation { continuation in
                startContinuation = continuation
                Task { @MainActor [weak self] in
                    guard let self, let stream = self.stream else {
                        self?.resumeStart(
                            throwing: VideoRecordingError.recordingDidNotStart
                        )
                        return
                    }
                    do {
                        try await stream.startCapture()
                    } catch {
                        self.resumeStart(throwing: error)
                    }
                }
            }
        } catch {
            await discardCurrentRecording()
            throw error
        }
    }

    func stop() async throws -> URL {
        guard let stream, let output = recordingOutput else {
            throw VideoRecordingError.recordingDidNotStart
        }

        do {
            try await withCheckedThrowingContinuation { continuation in
                finishContinuation = continuation
                do {
                    try stream.removeRecordingOutput(output)
                } catch {
                    resumeFinish(throwing: error)
                }
            }
            try await stream.stopCapture()

            guard let temporaryURL,
                  let destinationURL,
                  FileManager.default.fileExists(atPath: temporaryURL.path)
            else {
                throw VideoRecordingError.recordingFailed(
                    "o arquivo temporário não foi finalizado"
                )
            }
            try FileManager.default.moveItem(
                at: temporaryURL,
                to: destinationURL
            )
            reset()
            return destinationURL
        } catch {
            await discardCurrentRecording()
            throw error
        }
    }

    func cancel() async {
        await discardCurrentRecording()
    }

    private func discardCurrentRecording() async {
        if let stream {
            try? await stream.stopCapture()
        }
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        resumeStart(throwing: VideoRecordingError.recordingDidNotStart)
        resumeFinish(
            throwing: VideoRecordingError.recordingFailed(
                "a captura foi interrompida"
            )
        )
        reset()
    }

    private func reset() {
        stream = nil
        recordingOutput = nil
        temporaryURL = nil
        destinationURL = nil
        startContinuation = nil
        finishContinuation = nil
        didStart = false
    }

    private func resumeStart(throwing error: Error? = nil) {
        guard let continuation = startContinuation else { return }
        startContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            didStart = true
            continuation.resume()
        }
    }

    private func resumeFinish(throwing error: Error? = nil) {
        guard let continuation = finishContinuation else { return }
        finishContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func handleFailure(_ error: Error) {
        if startContinuation != nil {
            resumeStart(throwing: error)
        } else if finishContinuation != nil {
            resumeFinish(throwing: error)
        } else if didStart {
            onUnexpectedFailure?(error)
        }
    }

    nonisolated static func availableDestination(
        in directory: URL,
        date: Date = Date()
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let baseName = "\(formatter.string(from: date))_video-laudo"

        var suffix = 1
        var candidate = directory.appendingPathComponent("\(baseName).mp4")
        while FileManager.default.fileExists(atPath: candidate.path) {
            suffix += 1
            candidate = directory.appendingPathComponent(
                "\(baseName)-\(suffix).mp4"
            )
        }
        return candidate
    }
}

extension ScreenCaptureRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(
        _ recordingOutput: SCRecordingOutput
    ) {
        Task { @MainActor [weak self] in
            self?.resumeStart()
        }
    }

    nonisolated func recordingOutput(
        _ recordingOutput: SCRecordingOutput,
        didFailWithError error: any Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let wrapped = VideoRecordingError.recordingFailed(
                error.localizedDescription
            )
            self.handleFailure(wrapped)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(
        _ recordingOutput: SCRecordingOutput
    ) {
        Task { @MainActor [weak self] in
            self?.resumeFinish()
        }
    }
}

extension ScreenCaptureRecorder: SCStreamDelegate {
    nonisolated func stream(
        _ stream: SCStream,
        didStopWithError error: any Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let wrapped = VideoRecordingError.recordingFailed(
                error.localizedDescription
            )
            self.handleFailure(wrapped)
        }
    }
}
