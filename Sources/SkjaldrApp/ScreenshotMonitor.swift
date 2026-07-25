import Foundation
import UniformTypeIdentifiers

@MainActor
final class ScreenshotMonitor: ObservableObject {
    private struct FileSignature: Equatable {
        let size: Int
        let modificationDate: Date?
    }

    @Published private(set) var isRunning = false
    @Published private(set) var directory: URL?

    private var timer: Timer?
    private var knownFiles: [URL: FileSignature] = [:]
    private var pendingFiles: [URL: FileSignature] = [:]
    private var onReady: ((URL) -> Void)?

    func start(directory: URL, onReady: @escaping (URL) -> Void) {
        stop()
        self.directory = directory.standardizedFileURL
        self.onReady = onReady
        knownFiles = Dictionary(
            uniqueKeysWithValues: imageFiles(in: directory).compactMap { url in
                fileSignature(for: url).map { (url, $0) }
            }
        )
        pendingFiles.removeAll()
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scan()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        pendingFiles.removeAll()
        onReady = nil
    }

    private func scan() {
        guard let directory else { return }
        let files = imageFiles(in: directory)
        let currentURLs = Set(files)
        knownFiles = knownFiles.filter { currentURLs.contains($0.key) }
        pendingFiles = pendingFiles.filter { currentURLs.contains($0.key) }

        for url in files {
            guard let signature = fileSignature(for: url),
                  knownFiles[url] != signature
            else {
                continue
            }
            if pendingFiles[url] == signature, signature.size > 0 {
                knownFiles[url] = signature
                pendingFiles.removeValue(forKey: url)
                onReady?(url)
            } else {
                pendingFiles[url] = signature
            }
        }
    }

    private func fileSignature(for url: URL) -> FileSignature? {
        guard let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        ), let size = values.fileSize else {
            return nil
        }
        return FileSignature(
            size: max(0, size),
            modificationDate: values.contentModificationDate
        )
    }

    private func imageFiles(in directory: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return files.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let type = values.contentType
            else {
                return false
            }
            return type.conforms(to: .image)
        }
    }
}
