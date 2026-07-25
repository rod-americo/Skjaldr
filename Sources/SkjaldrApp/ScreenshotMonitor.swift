import Foundation
import UniformTypeIdentifiers

@MainActor
final class ScreenshotMonitor: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var directory: URL?

    private var timer: Timer?
    private var knownFiles = Set<URL>()
    private var pendingSizes: [URL: UInt64] = [:]
    private var onReady: ((URL) -> Void)?

    func start(directory: URL, onReady: @escaping (URL) -> Void) {
        stop()
        self.directory = directory.standardizedFileURL
        self.onReady = onReady
        knownFiles = Set(imageFiles(in: directory))
        pendingSizes.removeAll()
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
        pendingSizes.removeAll()
        onReady = nil
    }

    private func scan() {
        guard let directory else { return }
        for url in imageFiles(in: directory) where !knownFiles.contains(url) {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
            let current = UInt64(max(0, size))
            if pendingSizes[url] == current, current > 0 {
                knownFiles.insert(url)
                pendingSizes.removeValue(forKey: url)
                onReady?(url)
            } else {
                pendingSizes[url] = current
            }
        }
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
