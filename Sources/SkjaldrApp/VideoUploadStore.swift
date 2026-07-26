import AppKit
import Foundation
import OSLog

@MainActor
final class VideoUploadStore: ObservableObject {
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
    private let queueURL: URL

    init() {
        deleteLocalAfterUpload = UserDefaults.standard.bool(
            forKey: "video.upload.deleteLocal"
        )
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Skjaldr")
        queueURL = directory.appendingPathComponent("video-upload-queue.json")
        if let data = try? Data(contentsOf: queueURL),
           let saved = try? JSONDecoder().decode(
               [PendingVideoUpload].self,
               from: data
           )
        {
            queue = saved.filter {
                FileManager.default.fileExists(atPath: $0.filePath)
            }
        }
        if !queue.isEmpty {
            workerTask = Task { [weak self] in await self?.processQueue() }
        }
    }

    func enqueue(_ fileURL: URL) {
        guard !queue.contains(where: { $0.filePath == fileURL.path }) else {
            return
        }
        queue.append(PendingVideoUpload(fileURL: fileURL))
        persistQueue()
        if workerTask == nil {
            workerTask = Task { [weak self] in await self?.processQueue() }
        }
    }

    func retry() {
        guard !queue.isEmpty else { return }
        queue[0].attempts = 0
        persistQueue()
        errorMessage = nil
        workerTask?.cancel()
        workerTask = Task { [weak self] in await self?.processQueue() }
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
        defer { workerTask = nil }
        while !queue.isEmpty, !Task.isCancelled {
            do {
                try await uploadFirst()
                let completed = queue.removeFirst()
                persistQueue()
                if deleteLocalAfterUpload {
                    try? FileManager.default.removeItem(at: completed.fileURL)
                }
            } catch {
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

    private func uploadFirst() async throws {
        guard !queue.isEmpty else { return }
        var job = queue[0]
        let configuration: CloudUploadConfiguration
        do {
            configuration = try CloudUploadConfiguration.load()
        } catch CocoaError.fileNoSuchFile {
            throw VideoUploadError.notConfigured
        }
        guard configuration.uploadEnabled else { return }

        phase = .preparing
        errorMessage = nil
        publicURL = nil
        progress = 0
        let prepared = try await VideoUploadPreparation.prepare(job.fileURL)
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
                        publicURL = resource.publicURL
                        phase = .completed
                        copyLink()
                        return
                    }
                    throw VideoUploadError.invalidResponse
                }
                phase = .uploading
                let uploader = VideoFileUploader()
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
                publicURL = completed.publicURL
                phase = .completed
                copyLink()
                logger.notice("upload_completed: \(completed.id, privacy: .public)")
                return
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

    private func persistQueue() {
        do {
            try FileManager.default.createDirectory(
                at: queueURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(queue)
            try data.write(to: queueURL, options: .atomic)
        } catch {
            logger.error("Não foi possível persistir a fila de upload")
        }
    }
}
