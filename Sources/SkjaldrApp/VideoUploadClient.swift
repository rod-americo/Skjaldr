import AVFoundation
import CryptoKit
import Foundation

struct PreparedVideo {
    let fileURL: URL
    let sizeBytes: Int64
    let durationSeconds: Double
    let sha256: String
}

enum VideoUploadPreparation {
    static func prepare(_ url: URL) async throws -> PreparedVideo {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            guard let size = attributes[.size] as? NSNumber,
                  size.int64Value > 0
            else {
                throw VideoUploadError.invalidFile
            }
            guard size.int64Value <= 1_073_741_824 else {
                throw VideoUploadError.fileTooLarge
            }

            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration).seconds
            guard playable, duration.isFinite, duration > 0 else {
                throw VideoUploadError.invalidVideo
            }

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let data = try handle.read(upToCount: 1_048_576),
                  !data.isEmpty
            {
                try Task.checkCancellation()
                hasher.update(data: data)
            }
            let digest = hasher.finalize()
                .map { String(format: "%02x", $0) }
                .joined()
            return PreparedVideo(
                fileURL: url,
                sizeBytes: size.int64Value,
                durationSeconds: duration,
                sha256: digest
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

struct VideoUploadAPIClient {
    let configuration: CloudUploadConfiguration

    func create(
        _ video: PreparedVideo,
        idempotencyKey: String
    ) async throws -> RemoteVideoResource {
        let body = CreateVideoRequest(
            idempotencyKey: idempotencyKey,
            sizeBytes: video.sizeBytes,
            durationSeconds: video.durationSeconds,
            sha256: video.sha256
        )
        return try await request(
            path: "/api/videos",
            method: "POST",
            body: body
        )
    }

    func complete(id: String) async throws -> RemoteVideoResource {
        try await request(
            path: "/api/videos/\(id)/complete",
            method: "POST",
            body: Optional<String>.none
        )
    }

    private func request<Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> RemoteVideoResource {
        var request = URLRequest(
            url: configuration.baseURL.appendingPathComponent(path)
        )
        request.httpMethod = method
        request.setValue(
            "Bearer \(configuration.apiToken)",
            forHTTPHeaderField: "Authorization"
        )
        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VideoUploadError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data))
                .flatMap { $0 as? [String: String] }?["error"]
                ?? "HTTP \(http.statusCode)"
            throw VideoUploadError.remote(message)
        }
        return try JSONDecoder().decode(RemoteVideoResource.self, from: data)
    }
}

final class VideoFileUploader: NSObject,
    URLSessionTaskDelegate,
    URLSessionDataDelegate
{
    private var continuation: CheckedContinuation<Void, Error>?
    private var responseData = Data()
    private var progress: (@Sendable (Int64, Int64) -> Void)?
    private var session: URLSession?
    private var uploadTask: URLSessionUploadTask?

    func upload(
        fileURL: URL,
        uploadURL: URL,
        headers: [String: String],
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        self.progress = progress
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 3_600
            let session = URLSession(
                configuration: configuration,
                delegate: self,
                delegateQueue: nil
            )
            self.session = session
            let uploadTask = session.uploadTask(
                with: request,
                fromFile: fileURL
            )
            self.uploadTask = uploadTask
            uploadTask.resume()
        }
    }

    func cancel() {
        uploadTask?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        progress?(totalBytesSent, totalBytesExpectedToSend)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        responseData.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer {
            self.session?.finishTasksAndInvalidate()
            self.session = nil
            self.uploadTask = nil
            self.progress = nil
            responseData.removeAll()
        }
        if let error {
            continuation?.resume(throwing: error)
        } else if let response = task.response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode)
        {
            continuation?.resume()
        } else {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            continuation?.resume(
                throwing: VideoUploadError.remote("HTTP \(status)")
            )
        }
        continuation = nil
    }
}
