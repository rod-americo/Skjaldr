import AppKit
import Foundation

struct ClipboardManager {
    let temporaryDirectory: URL
    var pasteboard: NSPasteboard = .general

    func copy(_ rendered: RenderedComposition) throws {
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        removeExpiredTemporaryFiles()

        let item = NSPasteboardItem()
        item.setData(rendered.pngData, forType: .png)
        item.setData(rendered.tiffData, forType: .tiff)

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func removeExpiredTemporaryFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files {
            let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let date, date < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
