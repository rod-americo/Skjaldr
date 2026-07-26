import AppKit
import Foundation
import OSLog

@MainActor
final class VideoUploadStore: ObservableObject {
    var onUploadCompleted: ((URL) -> Void)?
    var onLocalFileDeleted: ((URL) -> Void)?

    @Published private(set) var phase: VideoUploadPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var sentBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var publicURL: URL?
    @Published private(set) var errorMessage: String?
    @Published var deleteLocalAfterUpload: Bool {
        didSet {
            UserDefaults.standard.set(
                deleteLocalAfterUpload,
                forKey: "video.upload.deleteLocal"
            )
        }
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.skjaldr.app",
        category: "VideoUpload"
    )
    private var queue: [PendingVideoUpload] = []
    private var workerTask: Task<Void, Never>?
    private var activeUploader: VideoFileUploader?
    private var isSuspendedForRecording = false
    private var shouldResumeWorker = false
    private let queueURL: URL

    init(queueURL customQueueURL: URL? = nil) {
        deleteLocalAfterUpload = UserDefaults.standard.bool(
            forKey: "video.upload.deleteLocal"
        )
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Skjaldr")
        queueURL = customQueueURL
            ?? directory.appendingPathComponent("video-upload-queue.json")
        if let data = try? Data(contentsOf: queueURL),
           let saved = try? JSONDecoder().decode(
               [PendingVideoUpload].self,
               from: data
           )
        {
            queue = saved.compactMap {
                guard FileManager.default.fileExists(atPath: $0.filePath)
                else {
                    return nil
                }
                var job = $0
                if let optimizedFilePath = job.optimizedFilePath,
                   !FileManager.default.fileExists(
                    atPath: optimizedFilePath
                   )
                {
                    job.optimizedFilePath = nil
                }
                return job
            }
        }
        startWorkerIfNeeded()
    }

    func enqueue(_ fileURL: URL) {
        guard !queue.contains(where: { $0.filePath == fileURL.path }) else {
            return
        }
        queue.append(PendingVideoUpload(fileURL: fileURL))
        guard persistQueue() else {
            errorMessage = VideoUploadError.queuePersistence.localizedDescription
            phase = .failed
            return
        }
        startWorkerIfNeeded()
    }

    func retry() {
        guard !queue.isEmpty else { return }
        queue[0].attempts = 0
        persistQueue()
        errorMessage = nil
        if let workerTask {
            shouldResumeWorker = true
            workerTask.cancel()
        } else {
            startWorkerIfNeeded()
        }
    }

    func suspendForVideoRecording() {
        guard !isSuspendedForRecording else { return }
        isSuspendedForRecording = true
        shouldResumeWorker = !queue.isEmpty
        workerTask?.cancel()
        activeUploader?.cancel()
    }

    func resumeAfterVideoRecording() {
        guard isSuspendedForRecording else { return }
        isSuspendedForRecording = false
        shouldResumeWorker = !queue.isEmpty
        startWorkerIfNeeded()
    }

    func copyLink() {
        guard let publicURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(
            publicURL.absoluteString,
            forType: .string
        ) else {
            errorMessage = VideoUploadError.clipboard.localizedDescription
            return
        }
    }

    func openLink() {
        guard let publicURL else { return }
        NSWorkspace.shared.open(publicURL)
    }

    private func processQueue() async {
        defer {
            workerTask = nil
            if shouldResumeWorker, !isSuspendedForRecording, !queue.isEmpty {
                shouldResumeWorker = false
                startWorkerIfNeeded()
            }
        }
        while !queue.isEmpty,
              !Task.isCancelled,
              !isSuspendedForRecording
        {
            do {
                if let completedURL = queue[0].completedPublicURL {
                    finalizeFirstJob(publicURL: completedURL)
                    continue
                }
                guard let completedURL = try await uploadFirst() else {
                    queue.removeFirst()
                    persistQueue()
                    phase = .idle
                    continue
                }
                queue[0].completedPublicURL = completedURL
                guard persistQueue() else {
                    throw VideoUploadError.queuePersistence
                }
                finalizeFirstJob(publicURL: completedURL)
            } catch {
                if isSuspendedForRecording ||
                    Task.isCancelled ||
                    (error as? URLError)?.code == .cancelled
                {
                    phase = .idle
                    shouldResumeWorker = !queue.isEmpty
                    return
                }
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                errorMessage = message
                phase = .failed
                logger.error(
                    "upload_failed: \(message, privacy: .public)"
                )
                persistQueue()
                return
            }
        }
    }

    private func finalizeFirstJob(publicURL: URL) {
        guard !queue.isEmpty else { return }
        let completed = queue[0]
        if deleteLocalAfterUpload {
            if let identity = completed.originalIdentity,
               VideoUploadOptimizer.fileMatches(
                completed.fileURL,
                expectedIdentity: identity
               )
            {
                do {
                    try FileManager.default.removeItem(
                        at: completed.fileURL
                    )
                    onLocalFileDeleted?(completed.fileURL)
                } catch {
                    logger.error(
                        "Upload concluído, mas o arquivo local foi preservado"
                    )
                }
            } else if FileManager.default.fileExists(
                atPath: completed.fileURL.path
            ) {
                logger.error(
                    """
                    Upload concluído; arquivo local alterado externamente \
                    foi preservado
                    """
                )
            }
            if let optimizedFilePath = completed.optimizedFilePath {
                try? FileManager.default.removeItem(
                    atPath: optimizedFilePath
                )
            }
        } else if let optimizedFilePath = completed.optimizedFilePath {
            let optimizedURL = URL(fileURLWithPath: optimizedFilePath)
            if FileManager.default.fileExists(atPath: optimizedURL.path),
               let identity = completed.originalIdentity
            {
                do {
                    try VideoUploadOptimizer.replaceOriginal(
                        at: completed.fileURL,
                        with: optimizedURL,
                        expectedIdentity: identity
                    )
                } catch {
                    logger.error(
                        """
                        Upload concluído, mas não foi possível substituir \
                        o vídeo local pela versão compacta
                        """
                    )
                    try? FileManager.default.removeItem(at: optimizedURL)
                }
            } else if FileManager.default.fileExists(atPath: optimizedURL.path) {
                logger.error(
                    """
                    Upload concluído; identidade do arquivo original ausente, \
                    mantendo a cópia local intacta
                    """
                )
                try? FileManager.default.removeItem(at: optimizedURL)
            }
        }

        queue.removeFirst()
        persistQueue()
        self.publicURL = publicURL
        phase = .completed
        copyLink()
        onUploadCompleted?(publicURL)
    }

    private func uploadFirst() async throws -> URL? {
        guard !queue.isEmpty else {
            throw VideoUploadError.invalidResponse
        }
        var job = queue[0]
        let configuration: CloudUploadConfiguration
        do {
            configuration = try CloudUploadConfiguration.load()
        } catch CocoaError.fileNoSuchFile {
            throw VideoUploadError.notConfigured
        }
        guard configuration.uploadEnabled else { return nil }

        phase = .preparing
        errorMessage = nil
        publicURL = nil
        progress = 0
        if job.optimizedFilePath == nil {
            let optimizedURL = VideoUploadOptimizer.destinationURL(
                for: job.fileURL,
                jobID: job.id
            )
            _ = try await VideoUploadOptimizer.optimize(
                sourceURL: job.fileURL,
                destinationURL: optimizedURL
            )
            job.optimizedFilePath = optimizedURL.path
            queue[0] = job
            guard persistQueue() else {
                throw VideoUploadError.queuePersistence
            }
        }
        let prepared = try await VideoUploadPreparation.prepare(
            job.uploadFileURL
        )
        totalBytes = prepared.sizeBytes

        let client = VideoUploadAPIClient(configuration: configuration)
        var lastError: Error?
        for attempt in job.attempts..<3 {
            do {
                job.attempts = attempt + 1
                queue[0] = job
                persistQueue()
                let resource = try await client.create(
                    prepared,
                    idempotencyKey: job.idempotencyKey
                )
                guard let uploadURL = resource.uploadURL,
                      let headers = resource.uploadHeaders
                else {
                    if resource.status == "available" {
                        return resource.publicURL
                    }
                    throw VideoUploadError.invalidResponse
                }
                phase = .uploading
                let uploader = VideoFileUploader()
                activeUploader = uploader
                defer { activeUploader = nil }
                try await uploader.upload(
                    fileURL: prepared.fileURL,
                    uploadURL: uploadURL,
                    headers: headers
                ) { [weak self] sent, total in
                    Task { @MainActor in
                        self?.sentBytes = sent
                        self?.totalBytes = total
                        self?.progress = total > 0
                            ? Double(sent) / Double(total)
                            : 0
                    }
                }
                phase = .confirming
                let completed = try await client.complete(id: resource.id)
                guard completed.status == "available" else {
                    throw VideoUploadError.invalidResponse
                }
                logger.notice("upload_completed: \(completed.id, privacy: .public)")
                return completed.publicURL
            } catch {
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(
                        for: .seconds(pow(2, Double(attempt + 1)))
                    )
                }
            }
        }
        throw lastError ?? VideoUploadError.invalidResponse
    }

    @discardableResult
    private func persistQueue() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: queueURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(queue)
            try data.write(to: queueURL, options: .atomic)
            return true
        } catch {
            logger.error("Não foi possível persistir a fila de upload")
            return false
        }
    }

    private func startWorkerIfNeeded() {
        guard workerTask == nil,
              !isSuspendedForRecording,
              !queue.isEmpty
        else {
            return
        }
        shouldResumeWorker = false
        workerTask = Task { [weak self] in
            await self?.processQueue()
        }
    }
}
